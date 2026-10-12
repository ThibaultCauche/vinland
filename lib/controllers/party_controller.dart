import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/party/party_models.dart';
import 'party_host_dj.dart';
import '../services/party/party_socket.dart';

enum PartyPhase {
  /// Pas de soiree.
  idle,

  /// Premiere connexion (creation ou entree) en cours.
  connecting,
  inParty,

  /// Connexion perdue : on revient tout seul avec le jeton.
  reconnecting,

  /// Soiree finie, ou on en a ete exclu : voir [PartyController.endReason].
  ended,
}

enum PartyEndReason { host, expired, kicked, banned, left, lost }

/// Etat d'une soiree vu par cet appareil, hote ou invite, et toutes les
/// actions du protocole (docs/soiree-protocole.md). Le relais applique les
/// regles (file equitable, limites, doublons) : ici on se contente
/// d'afficher ce qu'il renvoie, pour que tous les telephones voient la meme
/// file.
class PartyController extends ChangeNotifier implements PartyDjParty {
  PartyController({
    required PartySocketConnector connect,
    PartySeatStore? store,
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ],
    this.joinTimeout = const Duration(seconds: 8),
    DateTime Function()? now,
  })  : _connect = connect,
        _store = store,
        _now = now ?? DateTime.now;

  final PartySocketConnector _connect;
  final PartySeatStore? _store;
  final DateTime Function() _now;

  /// Attentes entre deux essais de reconnexion ; la derniere se repete tant
  /// que la soiree n'est pas quittee (le Wi-Fi d'un appartement plein peut
  /// rester capricieux un bon moment).
  final List<Duration> retryDelays;
  final Duration joinTimeout;

  PartySocket? _socket;
  StreamSubscription? _sub;
  Completer<bool>? _pendingJoin;
  bool _disposed = false;

  PartyPhase phase = PartyPhase.idle;
  PartyRole? role;
  PartyEndReason? endReason;

  /// Derniere erreur bloquante (entree refusee...), en francais.
  String? error;

  String? relayUrl;
  String? token;
  String? memberId;
  String partyName = '';

  /// Code court, connu seulement de l'hote.
  String? code;
  PartyRules rules = const PartyRules();
  DateTime? expiresAt;

  PartyQueueState queue = const PartyQueueState();
  PartySong? nowPlaying;

  List<PartySong> searchResults = const [];
  bool searching = false;
  int _requestId = 0;

  final _notices = StreamController<String>.broadcast();

  /// Messages passagers a montrer en bas d'ecran (titre propose, refus...).
  Stream<String> get notices => _notices.stream;

  @override
  bool get isHost => role == PartyRole.host;
  @override
  bool get isInParty => phase == PartyPhase.inParty;
  @override
  List<PartyQueueItem> get queueItems => queue.items;
  @override
  String? get nowPlayingSongId => nowPlaying?.songId;
  bool get isActive =>
      phase == PartyPhase.inParty || phase == PartyPhase.reconnecting;

  // --- Entree -------------------------------------------------------------

  /// Lance une soiree. [auth] = parametres Subsonic de la session ({u,t,s}
  /// ou {u,apiKey}) : le relais les verifie aupres de Navidrome puis les
  /// oublie (sans compte, n'importe qui pourrait fouiller le catalogue).
  Future<bool> create({
    required String relayUrl,
    required String partyName,
    required String hostName,
    required Map<String, String> auth,
    PartyRules rules = const PartyRules(),
  }) =>
      _enter(relayUrl, {
        'type': 'party_create',
        'v': partyProtocolVersion,
        'name': partyName,
        'hostName': hostName,
        'auth': auth,
        'rules': rules.toJson(),
      });

  Future<bool> join({
    required String relayUrl,
    required String code,
    required String name,
  }) =>
      _enter(relayUrl, {
        'type': 'party_join',
        'v': partyProtocolVersion,
        'code': code,
        'name': name,
      });

  /// Place gardee d'une soiree pas encore finie, ou null.
  Future<PartySeat?> savedSeat() async {
    final seat = await _store?.load();
    if (seat == null) return null;
    if (!_now().isBefore(seat.expiresAt)) {
      await _store?.save(null);
      return null;
    }
    return seat;
  }

  /// Revient dans la soiree gardee (apres un redemarrage de l'app).
  Future<bool> resume() async {
    final seat = await savedSeat();
    if (seat == null) return false;
    return _enter(seat.relayUrl, _tokenJoin(seat.token));
  }

  Map<String, dynamic> _tokenJoin(String token) => {
        'type': 'party_join',
        'v': partyProtocolVersion,
        'token': token,
      };

  Future<bool> _enter(String url, Map<String, dynamic> first) async {
    await _closeSocket();
    _reset();
    relayUrl = url;
    phase = PartyPhase.connecting;
    _notify();
    final ok = await _open(url, first);
    if (!ok && phase == PartyPhase.connecting) {
      phase = PartyPhase.idle;
      _notify();
    }
    return ok;
  }

  /// Ouvre une connexion et envoie [first] ; vrai des que le relais
  /// confirme par `party_joined`.
  Future<bool> _open(String url, Map<String, dynamic> first) async {
    final PartySocket socket;
    try {
      socket = await _connect(url);
    } catch (_) {
      error = 'Relais injoignable. Vérifie le réseau.';
      return false;
    }
    if (_disposed) {
      await socket.close();
      return false;
    }
    _socket = socket;
    final pending = Completer<bool>();
    _pendingJoin = pending;
    _sub = socket.messages.listen(
      _onMessage,
      onDone: () => _onClosed(socket),
      cancelOnError: true,
    );
    socket.send(first);
    final ok = await pending.future.timeout(joinTimeout, onTimeout: () {
      error ??= 'Le relais ne répond pas.';
      return false;
    });
    _pendingJoin = null;
    if (!ok && identical(_socket, socket)) await _closeSocket();
    return ok;
  }

  // --- Messages du relais -------------------------------------------------

  void _onMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'party_joined':
        _onJoined(msg);
      case 'queue_state':
        queue = PartyQueueState.fromJson(msg);
      case 'now_playing':
        final song = msg['song'];
        nowPlaying = song is Map
            ? PartySong.fromJson(song.cast<String, dynamic>())
            : null;
      case 'suggested':
        _notices.add('Titre proposé !');
      case 'search_results':
        if (msg['requestId'] != _requestId) return;
        searching = false;
        final songs = msg['songs'];
        searchResults = songs is List
            ? songs
                .whereType<Map>()
                .map((s) => PartySong.fromJson(s.cast<String, dynamic>()))
                .toList()
            : const [];
      case 'party_code':
        if (msg['code'] is String) code = msg['code'] as String;
        _notices.add('Nouveau code : $code');
      case 'kicked':
        _finish(msg['banned'] == true
            ? PartyEndReason.banned
            : PartyEndReason.kicked);
      case 'party_ended':
        _finish(msg['reason'] == 'expired'
            ? PartyEndReason.expired
            : PartyEndReason.host);
      case 'party_error':
        _onError(msg);
      default:
        return;
    }
    _notify();
  }

  void _onJoined(Map<String, dynamic> msg) {
    role = msg['role'] == 'host' ? PartyRole.host : PartyRole.guest;
    token = msg['token'] as String?;
    memberId = msg['memberId'] as String?;
    partyName = msg['name'] is String ? msg['name'] as String : '';
    rules = PartyRules.fromJson(msg['rules']);
    if (msg['code'] is String) code = msg['code'] as String;
    final expires = msg['expiresAt'];
    expiresAt =
        expires is int ? DateTime.fromMillisecondsSinceEpoch(expires) : null;
    phase = PartyPhase.inParty;
    error = null;
    final seatToken = token, url = relayUrl, end = expiresAt;
    if (seatToken != null && url != null && end != null) {
      unawaited(_store?.save(PartySeat(
        relayUrl: url,
        token: seatToken,
        role: role!,
        partyName: partyName,
        expiresAt: end,
      )));
    }
    _pendingJoin?.complete(true);
  }

  void _onError(Map<String, dynamic> msg) {
    final code = msg['code'] is String ? msg['code'] as String : '';
    final text = partyErrorMessage(code);
    final pending = _pendingJoin;
    if (pending != null && !pending.isCompleted) {
      error = text;
      // Jeton refuse pendant une reconnexion : la soiree n'existe plus
      // (relais redemarre) ou on en a ete banni, inutile d'insister.
      if (phase == PartyPhase.reconnecting &&
          const {'bad_token', 'expired', 'banned'}.contains(code)) {
        _finish(code == 'banned' ? PartyEndReason.banned : PartyEndReason.lost);
      }
      pending.complete(false);
      return;
    }
    if (msg['requestId'] != null && msg['requestId'] == _requestId) {
      searching = false;
    }
    _notices.add(text);
  }

  void _onClosed(PartySocket socket) {
    if (!identical(_socket, socket)) return;
    _socket = null;
    _sub = null;
    final pending = _pendingJoin;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    if (phase == PartyPhase.inParty) unawaited(_reconnect());
  }

  Future<void> _reconnect() async {
    phase = PartyPhase.reconnecting;
    _notify();
    var attempt = 0;
    while (!_disposed && phase == PartyPhase.reconnecting) {
      final delay = retryDelays[attempt.clamp(0, retryDelays.length - 1)];
      attempt++;
      await Future.delayed(delay);
      if (_disposed || phase != PartyPhase.reconnecting) return;
      final url = relayUrl, seatToken = token;
      if (url == null || seatToken == null) break;
      error = null;
      if (await _open(url, _tokenJoin(seatToken))) {
        _notify();
        return;
      }
    }
  }

  void _finish(PartyEndReason reason) {
    endReason = reason;
    phase = PartyPhase.ended;
    searching = false;
    unawaited(_store?.save(null));
    unawaited(_closeSocket());
  }

  // --- Actions ------------------------------------------------------------

  void _send(Map<String, dynamic> msg) {
    final socket = _socket;
    if (socket == null || phase != PartyPhase.inParty) {
      _notices.add('Connexion perdue, on réessaie…');
      return;
    }
    socket.send(msg);
  }

  /// Recherche dans le catalogue (2 caracteres minimum, comme le relais).
  /// Seule la reponse a la derniere recherche est gardee.
  void search(String query) {
    final q = query.trim();
    if (q.length < 2) {
      searchResults = const [];
      searching = false;
      _notify();
      return;
    }
    searching = true;
    _notify();
    _send({'type': 'search', 'requestId': ++_requestId, 'query': q});
  }

  void suggest(PartySong song) => _send({'type': 'suggest', ...song.toJson()});

  /// [value] : 1, -1, ou 0 pour retirer son vote.
  void vote(String itemId, int value) {
    if (!rules.votesEnabled) return;
    _send({'type': 'vote', 'itemId': itemId, 'value': value});
  }

  void veto(String itemId) => _send({'type': 'veto', 'itemId': itemId});

  void kick(String memberId, {bool ban = false}) =>
      _send({'type': 'kick', 'memberId': memberId, 'ban': ban});

  void rotateCode() => _send({'type': 'party_rotate_code'});

  /// L'hote annonce ce qui joue : un titre de la file ([itemId], qui la
  /// quitte alors), un titre hors file ([song]), ou rien (arret).
  @override
  void announceNowPlaying({String? itemId, PartySong? song}) => _send({
        'type': 'now_playing',
        if (itemId != null) 'itemId': itemId,
        if (itemId == null && song != null) ...song.toJson(),
      });

  /// Hote : termine la soiree pour tout le monde.
  Future<void> end() async {
    _send({'type': 'party_end'});
    _finish(PartyEndReason.host);
    _notify();
  }

  /// Invite : quitte la soiree (le relais garde sa place, mais on oublie
  /// le jeton ici : revenir demandera de rescanner le code).
  Future<void> leave() async {
    if (_socket != null) _socket!.send({'type': 'party_leave'});
    _finish(PartyEndReason.left);
    _notify();
  }

  /// Retour a l'etat initial apres l'ecran de fin.
  void clear() {
    unawaited(_closeSocket());
    _reset();
    _notify();
  }

  void _reset() {
    phase = PartyPhase.idle;
    role = null;
    endReason = null;
    error = null;
    token = null;
    memberId = null;
    code = null;
    partyName = '';
    rules = const PartyRules();
    expiresAt = null;
    queue = const PartyQueueState();
    nowPlaying = null;
    searchResults = const [];
    searching = false;
  }

  Future<void> _closeSocket() async {
    final socket = _socket, sub = _sub;
    _socket = null;
    _sub = null;
    await sub?.cancel();
    await socket?.close();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_closeSocket());
    _notices.close();
    super.dispose();
  }
}
