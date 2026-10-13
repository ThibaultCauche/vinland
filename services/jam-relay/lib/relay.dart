// Relais WebSocket pour l'ecoute synchronisee ("Jam") de Vinland.
//
// Volontairement "bete" : ce service ne connait rien de Navidrome, de la
// musique ou des comptes utilisateurs au-dela d'un pseudo declaratif (voir
// _Peer.username, jamais verifie -- coherent avec le modele "cercle proche"
// du sessionId partage). Il ne fait que rediffuser, a tous les participants
// d'une session, l'etat de lecture envoye par l'hote de cette session
// (modele hote-autoritaire : un seul appareil pilote play/pause/seek/
// changement de titre, les autres suivent en miroir cote client) -- sauf
// pour un transfert d'hebergement explicite (voir 'transfer_host'), qui
// permet a l'hote de ceder la main a un participant nomme sans casser la
// session pour tout le monde.
//
// Deux secrets distincts (protocole v2, session 05 du plan) :
// - le sessionId sert a REJOINDRE : quiconque le connait peut ecouter et
//   envoyer des commandes a l'hote. Il est partage entre amis (code, ou
//   mirroir "now playing" visible depuis la page Amis).
// - le hostSecret sert a PILOTER : il est remis a l'hote a la creation de
//   la session et a lui seul. Reprendre l'hebergement d'une session qui
//   existe deja exige ce secret. Avant la v2, n'importe qui connaissant le
//   sessionId pouvait envoyer 'host' et retrograder l'hote en place (scenario
//   de detournement de l'audit du 29/09/2026), alors que ce sessionId est
//   justement fait pour circuler.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'party/party_hub.dart';

/// Version du protocole parlee par ce relais, ajoutee a chaque message
/// envoye (champ "v"). Les clients 1.2.x n'envoient pas de "v" : ils restent
/// acceptes (meme forme de messages), seule la reprise d'hebergement sans
/// secret leur est desormais refusee.
const protocolVersion = 2;

/// Limites du relais. Valeurs par defaut adaptees a un usage "cercle
/// proche" sur un NAS ; surchargeables par variables d'environnement (voir
/// RelayLimits.fromEnvironment) pour les tests ou un usage plus large.
class RelayLimits {
  /// Taille max d'un message recu, en octets. Plus large que les 64 Ko du
  /// plan : un 'state' porte la file d'attente complete de l'hote quand elle
  /// change (queueIds, ~25 octets par titre), et une file "toute la
  /// bibliotheque en aleatoire" depasse vite 2 500 titres.
  final int maxMessageBytes;
  final int maxSessions;
  final int maxPeersPerSession;

  /// Connexions ouvertes simultanement, toutes sessions confondues (y
  /// compris celles qui n'ont encore rien envoye).
  final int maxConnections;

  /// Delai laisse a une connexion pour envoyer 'host' ou 'join' : au-dela,
  /// elle est fermee (evite d'accumuler des sockets inertes).
  final Duration handshakeTimeout;

  /// Ping WebSocket : detecte les appareils disparus sans fermeture propre
  /// (telephone passe hors reseau), qui sinon restaient "participants" et
  /// gardaient leur session ouverte indefiniment.
  final Duration pingInterval;

  const RelayLimits({
    this.maxMessageBytes = 256 * 1024,
    this.maxSessions = 200,
    this.maxPeersPerSession = 50,
    this.maxConnections = 1000,
    this.handshakeTimeout = const Duration(seconds: 30),
    this.pingInterval = const Duration(seconds: 20),
  });

  factory RelayLimits.fromEnvironment(Map<String, String> env) {
    const d = RelayLimits();
    int read(String key, int fallback) =>
        int.tryParse(env[key] ?? '') ?? fallback;
    return RelayLimits(
      maxMessageBytes: read('MAX_MESSAGE_BYTES', d.maxMessageBytes),
      maxSessions: read('MAX_SESSIONS', d.maxSessions),
      maxPeersPerSession: read('MAX_PEERS_PER_SESSION', d.maxPeersPerSession),
      maxConnections: read('MAX_CONNECTIONS', d.maxConnections),
      handshakeTimeout: Duration(
          seconds:
              read('HANDSHAKE_TIMEOUT_SECONDS', d.handshakeTimeout.inSeconds)),
      pingInterval: Duration(
          seconds: read('PING_INTERVAL_SECONDS', d.pingInterval.inSeconds)),
    );
  }
}

/// sessionId accepte : caracteres base64url/hex seulement, 8 a 128. Le
/// minimum de 8 garde compatibles les codes Jam des clients 1.2.x (6 octets
/// aleatoires, 8 caracteres) ; les clients v2 en generent 16 octets.
final _sessionIdPattern = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

/// Un hostSecret fourni par le client (synchro perso : derive du secret du
/// compte, pour que tous les appareils du compte puissent reprendre la main)
/// doit etre au moins aussi long qu'un secret genere ici.
const _minClientHostSecretLength = 32;

class _Peer {
  final WebSocketChannel channel;
  String? username;
  bool isHost = false;
  String? sessionId;

  /// A envoye au moins un message du mode Soiree : la connexion n'entre
  /// jamais dans une session Jam, le delai de 'host'/'join' ne s'applique
  /// pas (un invite reste connecte toute la soiree).
  bool inParty = false;
  _Peer(this.channel);
}

/// Connexion vue par PartyHub. Messages envoyes tels quels : le mode Soiree
/// a son propre numero de protocole (champ "v" ecrit par PartyHub), il ne
/// faut pas l'ecraser par celui du Jam.
class _PartyConnection implements PartyConnection {
  final WebSocketChannel channel;
  _PartyConnection(this.channel);

  @override
  void send(Map<String, dynamic> message) {
    try {
      channel.sink.add(jsonEncode(message));
    } catch (_) {
      // Connexion deja fermee : PartyHub.disconnected fera le menage.
    }
  }

  @override
  void close() => channel.sink.close();
}

class _Session {
  final String id;
  _Peer? host;
  String hostSecret;
  final Set<_Peer> participants = {};

  _Session(this.id, this.hostSecret);

  int get participantCount => participants.length;
}

class JamRelay {
  final RelayLimits limits;

  /// Mode Soiree (voir bin/server.dart, qui le configure selon les
  /// variables d'environnement). Null : messages de soiree ignores.
  final PartyHub? party;
  final void Function(String line) _log;
  final Map<String, _Session> _sessions = {};
  final Random _random = Random.secure();
  int _connections = 0;

  JamRelay(
      {this.limits = const RelayLimits(),
      this.party,
      void Function(String)? log})
      : _log = log ?? ((line) => stderr.writeln('jam_relay: $line'));

  int get sessionCount => _sessions.length;

  /// Handler shelf a monter sur le chemin /jam (voir bin/server.dart).
  Handler get handler => webSocketHandler(
        (WebSocketChannel channel, String? _) => _handleConnection(channel),
        pingInterval: limits.pingInterval,
      );

  String _newSecret() => base64Url
      .encode(List.generate(32, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  void _handleConnection(WebSocketChannel channel) {
    if (_connections >= limits.maxConnections) {
      _sendError(channel, 'relais plein');
      channel.sink.close();
      _log('refus: trop de connexions');
      return;
    }
    _connections++;
    final peer = _Peer(channel);
    final partyConn = _PartyConnection(channel);
    final handshake = Timer(limits.handshakeTimeout, () {
      if (peer.sessionId == null && !peer.inParty) channel.sink.close();
    });

    channel.stream.listen(
      (raw) {
        // Taille mesuree en caracteres pour un message texte : borne basse
        // du nombre d'octets UTF-8, suffisant pour ecarter les abus.
        final size = raw is String ? raw.length : (raw as List).length;
        if (size > limits.maxMessageBytes) {
          _sendError(channel, 'message trop gros');
          _log('refus: message de $size octets, connexion fermee');
          channel.sink.close();
          return;
        }
        if (raw is! String) return;
        Map<String, dynamic> msg;
        try {
          msg = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        final party = this.party;
        if (party != null && party.handles(msg['type'])) {
          peer.inParty = true;
          // Un message de soiree mal forme ne doit jamais faire tomber le
          // relais (et donc les Jam en cours).
          party
              .handle(partyConn, msg, rawLength: size)
              .catchError((Object e) => _log('soiree : $e'));
          return;
        }
        _onMessage(peer, msg);
      },
      onDone: () {
        handshake.cancel();
        _connections--;
        party?.disconnected(partyConn);
        _handleDisconnect(peer);
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _onMessage(_Peer peer, Map<String, dynamic> msg) {
    final channel = peer.channel;
    switch (msg['type']) {
      case 'host':
        {
          final id = msg['sessionId']?.toString();
          if (id == null || !_sessionIdPattern.hasMatch(id)) {
            _sendError(channel, 'sessionId invalide');
            return;
          }
          if (peer.sessionId != null && peer.sessionId != id) {
            _sendError(channel, 'deja dans une autre session');
            return;
          }
          final providedSecret = msg['hostSecret']?.toString();
          var session = _sessions[id];
          if (session == null) {
            if (_sessions.length >= limits.maxSessions) {
              _sendError(channel, 'relais plein');
              _log('refus: nombre max de sessions atteint');
              return;
            }
            final secret = (providedSecret != null &&
                    providedSecret.length >= _minClientHostSecretLength)
                ? providedSecret
                : _newSecret();
            session = _Session(id, secret);
            _sessions[id] = session;
            _log('session creee (${_sessions.length} actives)');
          } else if (session.host != peer &&
              (providedSecret == null ||
                  !_constantTimeEquals(providedSecret, session.hostSecret))) {
            // Coeur du correctif : une session existante ne change d'hote
            // que si l'on prouve qu'on en est (ou qu'on en partage) l'hote.
            _sendError(channel, 'hebergement refuse');
            _log('refus: reprise d\'hebergement sans le bon secret');
            return;
          }
          final previousHost = session.host;
          session.participants.remove(peer);
          peer.username = msg['username']?.toString();
          peer.isHost = true;
          peer.sessionId = id;
          session.host = peer;
          _send(channel, {
            'type': 'joined',
            'sessionId': id,
            'role': 'host',
            'hostSecret': session.hostSecret,
          });
          // Un hote precedent existait deja sur ce sessionId (autre appareil
          // du meme compte qui "reprend ici" la synchro perso, voir
          // AppState._maybeBecomePersonalHost) : le retrograder en
          // participant plutot que de le laisser croire a tort qu'il pilote
          // toujours (il pourrait continuer a diffuser un 'state'
          // concurrent, voir le cas 'state' qui verifie l'identite du peer).
          if (previousHost != null && previousHost != peer) {
            previousHost.isHost = false;
            session.participants.add(previousHost);
            _send(previousHost.channel, {
              'type': 'host_transferred',
              'role': 'participant',
            });
          }
          _notifyParticipants(session);
          break;
        }

      case 'join':
        {
          final id = msg['sessionId']?.toString();
          final session = id == null ? null : _sessions[id];
          if (session == null) {
            _sendError(channel, 'session introuvable');
            return;
          }
          if (peer.sessionId != null) {
            _sendError(channel, 'deja dans une session');
            return;
          }
          if (session.participantCount >= limits.maxPeersPerSession) {
            _sendError(channel, 'session pleine');
            _log('refus: session pleine');
            return;
          }
          peer.username = msg['username']?.toString();
          peer.isHost = false;
          peer.sessionId = id;
          session.participants.add(peer);
          _send(channel,
              {'type': 'joined', 'sessionId': id, 'role': 'participant'});
          _notifyParticipants(session);
          break;
        }

      case 'state':
        {
          final session = _sessionOf(peer);
          // Verifie l'identite (pas seulement le drapeau local du peer) : un
          // hote retrograde par un transfert ne doit plus pouvoir rediffuser
          // son propre etat en parallele du nouvel hote.
          if (session == null || session.host != peer) return;
          // Rediffuse tel quel (trackId/positionMs/isPlaying/ts/queueIds) a
          // tous les participants -- aucune interpretation cote relais.
          for (final participant in session.participants) {
            _send(participant.channel, msg);
          }
          break;
        }

      case 'command':
        {
          // Un participant pilote l'hote a distance (play/pause/suivant/
          // precedent/ajout a la file) : transmis uniquement a l'hote,
          // jamais aux autres participants -- symetrique du cas 'state' qui
          // va hote -> tous.
          final session = _sessionOf(peer);
          if (session == null || session.host == peer) return;
          final host = session.host;
          if (host != null) _send(host.channel, msg);
          break;
        }

      case 'transfer_host':
        {
          // Delegation nominative (voir AppState.transferJamHost) : seul
          // l'hote actuel peut ceder, et seulement a un participant deja
          // present et nomme dans cette session.
          final session = _sessionOf(peer);
          if (session == null || session.host != peer) return;
          final targetUsername = msg['targetUsername']?.toString();
          _Peer? target;
          for (final p in session.participants) {
            if (p.username != null && p.username == targetUsername) {
              target = p;
              break;
            }
          }
          if (target == null) {
            _sendError(channel, 'participant introuvable');
            return;
          }
          session.participants.remove(target);
          peer.isHost = false;
          session.participants.add(peer);
          target.isHost = true;
          session.host = target;
          // Nouveau secret : l'ancien hote, redevenu simple participant, ne
          // doit plus pouvoir reprendre la main avec celui qu'il connaissait.
          session.hostSecret = _newSecret();
          _send(target.channel, {
            'type': 'host_transferred',
            'role': 'host',
            'hostSecret': session.hostSecret,
          });
          _send(channel, {'type': 'host_transferred', 'role': 'participant'});
          _notifyParticipants(session);
          break;
        }

      case 'ping':
        // Synchro d'horloge facon NTP (voir lib/domain/jam_sync.dart cote
        // app) : renvoie tout de suite l'heure du relais, seule horloge
        // commune a tous les appareils d'une session. Hors session aussi :
        // ne revele rien, et ne coute qu'un message.
        _send(channel, {
          'type': 'pong',
          'id': msg['id'],
          't0': msg['t0'],
          'relayTs': DateTime.now().millisecondsSinceEpoch,
        });
        break;

      case 'leave':
        channel.sink.close();
        break;
    }
  }

  _Session? _sessionOf(_Peer peer) {
    final id = peer.sessionId;
    return id == null ? null : _sessions[id];
  }

  void _handleDisconnect(_Peer peer) {
    final session = _sessionOf(peer);
    if (session == null) return;

    if (session.host == peer) {
      // Une session ne survit pas a son hote : pas de session orpheline qui
      // occuperait une place jusqu'au redemarrage du relais.
      for (final participant in session.participants) {
        _send(participant.channel, {'type': 'host_left'});
      }
      _sessions.remove(session.id);
      _log('session fermee (${_sessions.length} actives)');
    } else {
      session.participants.remove(peer);
      _notifyParticipants(session);
    }
  }

  void _notifyParticipants(_Session session) {
    final host = session.host;
    if (host == null) return;
    _send(host.channel, {
      'type': 'participant_count',
      'count': session.participantCount,
      // Pseudos declaratifs (voir _Peer.username) : permet a l'hote de
      // choisir a qui ceder l'hebergement (voir 'transfer_host') sans que le
      // relais n'ait besoin de connaitre les comptes Navidrome.
      'usernames': session.participants
          .map((p) => p.username)
          .whereType<String>()
          .toList(),
    });
  }

  void _sendError(WebSocketChannel channel, String message) {
    _send(channel, {'type': 'error', 'message': message});
  }

  void _send(WebSocketChannel channel, Map<String, dynamic> message) {
    try {
      channel.sink.add(jsonEncode({...message, 'v': protocolVersion}));
    } catch (_) {
      // Connexion deja fermee entre-temps -- ignore, onDone nettoiera.
    }
  }
}

/// Comparaison en temps constant : ne laisse pas deviner le secret octet
/// par octet a partir du temps de reponse.
bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
