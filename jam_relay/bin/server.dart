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
// Le sessionId (genere aleatoirement cote app, voir lib/services/
// jam_service.dart) sert de secret partage : quiconque le connait peut
// rejoindre. Pas d'autre authentification -- coherent avec un usage
// "cercle proche" ou le sessionId est partage directement entre amis.
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Peer {
  final WebSocketChannel channel;
  String? username;
  bool isHost = false;
  _Peer(this.channel);
}

class _Session {
  final String id;
  _Peer? host;
  final Set<_Peer> participants = {};

  _Session(this.id);

  int get participantCount => participants.length;
}

final Map<String, _Session> _sessions = {};

void main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8765;

  final handler = webSocketHandler((WebSocketChannel channel, String? _) {
    _handleConnection(channel);
  });

  final server = await shelf_io.serve(
    // Un seul chemin ("/jam") : c'est celui que tailscale serve doit router
    // vers ce service, sur le meme hostname Funnel que Navidrome.
    (Request request) {
      if (request.url.path == 'jam' || request.url.path == '') {
        return handler(request);
      }
      return Response.notFound('not found');
    },
    InternetAddress.anyIPv4,
    port,
  );
  stderr.writeln('jam_relay: en ecoute sur :${server.port}');
}

void _handleConnection(WebSocketChannel channel) {
  final peer = _Peer(channel);
  String? sessionId;

  channel.stream.listen(
    (raw) {
      Map<String, dynamic> msg;
      try {
        msg = jsonDecode(raw as String) as Map<String, dynamic>;
      } catch (_) {
        return;
      }

      switch (msg['type']) {
        case 'host':
          {
            final id = msg['sessionId']?.toString();
            if (id == null || id.isEmpty) {
              _sendError(channel, 'sessionId manquant');
              return;
            }
            final session = _sessions.putIfAbsent(id, () => _Session(id));
            final previousHost = session.host;
            peer.username = msg['username']?.toString();
            peer.isHost = true;
            session.host = peer;
            sessionId = id;
            _send(channel, {'type': 'joined', 'sessionId': id, 'role': 'host'});
            // Un hote precedent existait deja sur ce sessionId (reconnexion
            // apres coupure, ou prise de controle -- voir le cas 'host' cote
            // client dans JamService) : le retrograder en participant plutot
            // que de le laisser croire a tort qu'il pilote toujours (ancien
            // bug latent : son propre isHost local restait vrai, il pouvait
            // continuer a diffuser un 'state' concurrent, voir le cas
            // 'state' plus bas qui verifie desormais l'identite du peer).
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
            peer.username = msg['username']?.toString();
            peer.isHost = false;
            session.participants.add(peer);
            sessionId = id;
            _send(channel,
                {'type': 'joined', 'sessionId': id, 'role': 'participant'});
            _notifyParticipants(session);
            break;
          }

        case 'state':
          {
            final id = sessionId;
            if (id == null || !peer.isHost) return;
            final session = _sessions[id];
            // Verifie l'identite (pas seulement le drapeau local du peer) :
            // un hote retrograde par un transfert (voir le cas 'host'
            // ci-dessus) ne doit plus pouvoir rediffuser son propre etat en
            // parallele du nouvel hote.
            if (session == null || session.host != peer) return;
            // Rediffuse tel quel (trackId/positionMs/isPlaying/ts/queueIds)
            // a tous les participants -- aucune interpretation cote relais.
            for (final participant in session.participants) {
              _send(participant.channel, msg);
            }
            break;
          }

        case 'command':
          {
            // Un participant pilote l'hote a distance (play/pause/suivant/
            // precedent/ajout a la file) : transmis uniquement a l'hote,
            // jamais aux autres participants -- symetrique du cas 'state'
            // qui va hote -> tous.
            final id = sessionId;
            if (id == null || peer.isHost) return;
            final session = _sessions[id];
            final host = session?.host;
            if (host != null) _send(host.channel, msg);
            break;
          }

        case 'transfer_host':
          {
            // Delegation nominative (voir AppState.transferJamHost) :
            // seul l'hote actuel peut ceder, et seulement a un participant
            // deja present et nomme dans cette session.
            final id = sessionId;
            if (id == null || !peer.isHost) return;
            final session = _sessions[id];
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
            _send(target.channel,
                {'type': 'host_transferred', 'role': 'host'});
            _send(channel, {'type': 'host_transferred', 'role': 'participant'});
            _notifyParticipants(session);
            break;
          }

        case 'leave':
          channel.sink.close();
          break;
      }
    },
    onDone: () => _handleDisconnect(sessionId, peer),
    onError: (_) => _handleDisconnect(sessionId, peer),
    cancelOnError: true,
  );
}

void _handleDisconnect(String? sessionId, _Peer peer) {
  if (sessionId == null) return;
  final session = _sessions[sessionId];
  if (session == null) return;

  if (session.host == peer) {
    for (final participant in session.participants) {
      _send(participant.channel, {'type': 'host_left'});
    }
    _sessions.remove(sessionId);
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
    channel.sink.add(jsonEncode(message));
  } catch (_) {
    // Connexion deja fermee entre-temps -- ignore, onDone/onError nettoiera.
  }
}
