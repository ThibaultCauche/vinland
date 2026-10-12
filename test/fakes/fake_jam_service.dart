import 'dart:async';

import 'package:vinland/services/jam_service.dart';

/// Relais Jam en memoire, qui rejoue les regles de jam_relay/bin/server.dart
/// (prise de controle d'une session par un nouvel hote, depart de l'hote,
/// transfert d'hebergement...) pour faire discuter plusieurs
/// [FakeJamService] -- un par appareil simule -- sans reseau.
class FakeJamRelay {
  final Map<String, _FakeSession> _sessions = {};

  /// Sessions encore ouvertes (pour les assertions).
  Iterable<String> get sessionIds => _sessions.keys;

  /// Messages 'state' relayes, dans l'ordre (pour les assertions).
  final List<JamStateMessage> relayedStates = [];

  bool _host(FakeJamService peer, String id) {
    final session = _sessions.putIfAbsent(id, () => _FakeSession());
    final previous = session.host;
    session.participants.remove(peer);
    session.host = peer;
    peer._joined(id, host: true);
    if (previous != null && previous != peer) {
      session.participants.add(previous);
      previous._roleChanged(host: false);
    }
    _notifyHost(session);
    return true;
  }

  bool _join(FakeJamService peer, String id) {
    final session = _sessions[id];
    if (session == null) return false;
    session.participants.add(peer);
    peer._joined(id, host: false);
    _notifyHost(session);
    return true;
  }

  void _state(FakeJamService from, JamStateMessage msg) {
    final session = _sessions[from.sessionId];
    if (session == null || session.host != from) return;
    relayedStates.add(msg);
    for (final p in session.participants) {
      p._state.add(msg);
    }
  }

  void _command(FakeJamService from, JamCommandMessage cmd) {
    _sessions[from.sessionId]?.host?._command.add(cmd);
  }

  void _transfer(FakeJamService from, String targetUsername) {
    final session = _sessions[from.sessionId];
    if (session == null || session.host != from) return;
    final target = session.participants
        .where((p) => p.username == targetUsername)
        .firstOrNull;
    if (target == null) return;
    session.participants
      ..remove(target)
      ..add(from);
    session.host = target;
    target._roleChanged(host: true);
    from._roleChanged(host: false);
    _notifyHost(session);
  }

  void _leave(FakeJamService peer, String id) {
    final session = _sessions[id];
    if (session == null) return;
    if (session.host == peer) {
      _sessions.remove(id);
      for (final p in session.participants.toList()) {
        p._hostLeft();
      }
    } else {
      session.participants.remove(peer);
      _notifyHost(session);
    }
  }

  void _notifyHost(_FakeSession session) {
    final host = session.host;
    if (host == null) return;
    host._count.add(session.participants.length);
    host._participants
        .add(session.participants.map((p) => p.username).toList());
  }
}

class _FakeSession {
  FakeJamService? host;
  final Set<FakeJamService> participants = {};
}

/// Un appareil connecte au [FakeJamRelay]. Flux synchrones : chaque message
/// est traite pendant l'appel qui l'envoie, comme le ferait un relais
/// instantane.
class FakeJamService implements JamService {
  FakeJamService(this.relay, this.username);

  final FakeJamRelay relay;
  final String username;

  /// Commandes envoyees vers l'hote (pour les assertions).
  final List<String> sentCommands = [];

  /// Faire echouer le prochain host()/join() (relais injoignable).
  bool unreachable = false;

  int _nextSessionId = 1;
  String? _sessionId;
  bool _isHost = false;
  bool _active = false;

  final _state = StreamController<JamStateMessage>.broadcast(sync: true);
  final _hostLeftCtl = StreamController<void>.broadcast(sync: true);
  final _count = StreamController<int>.broadcast(sync: true);
  final _participants = StreamController<List<String>>.broadcast(sync: true);
  final _command = StreamController<JamCommandMessage>.broadcast(sync: true);
  final _transferred = StreamController<bool>.broadcast(sync: true);

  @override
  String? get sessionId => _sessionId;
  @override
  bool get isHost => _isHost;
  @override
  bool get isActive => _active;

  @override
  Stream<JamStateMessage> get stateStream => _state.stream;
  @override
  Stream<void> get hostLeftStream => _hostLeftCtl.stream;
  @override
  Stream<int> get participantCountStream => _count.stream;
  @override
  Stream<List<String>> get participantsStream => _participants.stream;
  @override
  Stream<JamCommandMessage> get commandStream => _command.stream;
  @override
  Stream<bool> get hostTransferredStream => _transferred.stream;

  @override
  String generateSessionId() => '$username-jam-${_nextSessionId++}';

  @override
  String personalSessionId(String username) => 'perso-$username';

  @override
  Future<bool> host(String sessionId) async {
    await leave();
    if (unreachable) return false;
    _active = true;
    return relay._host(this, sessionId);
  }

  @override
  Future<bool> join(String sessionId) async {
    await leave();
    if (unreachable) return false;
    _active = true;
    final ok = relay._join(this, sessionId);
    // Comme WebSocketJamService : une erreur du relais ferme la connexion.
    if (!ok) await leave();
    return ok;
  }

  void _joined(String id, {required bool host}) {
    _sessionId = id;
    _isHost = host;
  }

  void _roleChanged({required bool host}) {
    _isHost = host;
    _transferred.add(host);
  }

  void _hostLeft() {
    _hostLeftCtl.add(null);
    _closeLocally();
  }

  @override
  void sendState({
    required String trackId,
    required int positionMs,
    required bool isPlaying,
    String? deviceName,
    List<String>? queueIds,
  }) {
    if (!_isHost || !_active) return;
    relay._state(
      this,
      JamStateMessage(
        trackId: trackId,
        positionMs: positionMs,
        isPlaying: isPlaying,
        ts: DateTime.now().millisecondsSinceEpoch,
        deviceName: deviceName,
        queueIds: queueIds,
      ),
    );
  }

  @override
  void sendCommand(String action,
      {String? trackId, int? positionMs, String? deviceName}) {
    if (_isHost || !_active) return;
    sentCommands.add(trackId == null ? action : '$action:$trackId');
    relay._command(
      this,
      JamCommandMessage(action,
          trackId: trackId, positionMs: positionMs, deviceName: deviceName),
    );
  }

  @override
  void sendTransferHost(String targetUsername) {
    if (!_isHost || !_active) return;
    relay._transfer(this, targetUsername);
  }

  @override
  Future<void> leave() async {
    final id = _sessionId;
    if (_active && id != null) relay._leave(this, id);
    _closeLocally();
  }

  void _closeLocally() {
    _active = false;
    _sessionId = null;
    _isHost = false;
  }
}
