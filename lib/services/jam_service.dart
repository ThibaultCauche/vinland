import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'navidrome_service.dart';

class JamStateMessage {
  final String trackId;
  final int positionMs;
  final bool isPlaying;
  final int ts;
  final String? deviceName;

  const JamStateMessage({
    required this.trackId,
    required this.positionMs,
    required this.isPlaying,
    required this.ts,
    this.deviceName,
  });

  factory JamStateMessage.fromJson(Map<String, dynamic> json) =>
      JamStateMessage(
        trackId: json['trackId'] as String,
        positionMs: json['positionMs'] as int,
        isPlaying: json['isPlaying'] as bool,
        ts: json['ts'] as int,
        deviceName: json['deviceName'] as String?,
      );
}

/// Commande de controle a distance (play/pause/suivant/precedent), envoyee
/// par un participant et recue uniquement par l'hote -- voir sendCommand.
class JamCommandMessage {
  final String action;
  const JamCommandMessage(this.action);
}

/// Client du relais Jam (voir jam_relay/) : connexion WebSocket a un service
/// separe de Navidrome, expose sur le meme hostname Funnel sous /jam (voir
/// jam_relay/README.md). Modele hote-autoritaire : l'hote envoie son etat de
/// lecture via sendState(), les participants le recoivent via stateStream et
/// n'envoient jamais d'etat eux-memes.
class JamService {
  static final JamService _instance = JamService._internal();
  factory JamService() => _instance;
  JamService._internal();

  final NavidromeService _navidrome = NavidromeService();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? _sessionId;
  bool _isHost = false;

  String? get sessionId => _sessionId;
  bool get isHost => _isHost;
  bool get isActive => _channel != null;

  final _stateController = StreamController<JamStateMessage>.broadcast();
  Stream<JamStateMessage> get stateStream => _stateController.stream;

  final _hostLeftController = StreamController<void>.broadcast();
  Stream<void> get hostLeftStream => _hostLeftController.stream;

  final _participantCountController = StreamController<int>.broadcast();
  Stream<int> get participantCountStream => _participantCountController.stream;

  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  final _commandController = StreamController<JamCommandMessage>.broadcast();
  Stream<JamCommandMessage> get commandStream => _commandController.stream;

  String? _relayUrl() {
    final baseUrl = _navidrome.baseUrl;
    if (baseUrl == null || baseUrl.isEmpty) return null;
    final wsBase = baseUrl
        .replaceFirst(RegExp(r'^https'), 'wss')
        .replaceFirst(RegExp(r'^http'), 'ws');
    return '$wsBase/jam';
  }

  String generateSessionId() {
    final random = Random.secure();
    final bytes = List.generate(6, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// SessionId stable et prive pour la synchro multi-appareils "perso" (voir
  /// AppState._maybeBecomePersonalHost/_tryJoinPersonalSync) : deterministe a
  /// partir du compte Navidrome, pour que tous les appareils du meme compte
  /// se retrouvent automatiquement sans code a partager. Hashe (avec un sel
  /// fixe) plutot qu'utilise tel quel pour ne pas exposer le nom d'utilisateur
  /// Navidrome en clair a qui intercepterait ce sessionId.
  String personalSessionId(String username) {
    final digest = sha256.convert(utf8.encode('vinland_personal_$username'));
    return digest.toString().substring(0, 24);
  }

  Future<bool> host(String sessionId) => _connect(sessionId, asHost: true);

  Future<bool> join(String sessionId) => _connect(sessionId, asHost: false);

  Future<bool> _connect(String sessionId, {required bool asHost}) async {
    final url = _relayUrl();
    if (url == null) return false;
    await leave();

    final completer = Completer<bool>();
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      await channel.ready;
      _channel = channel;
      _sub = channel.stream.listen(
        (raw) => _onMessage(raw, completer),
        onError: (_) {
          if (!completer.isCompleted) completer.complete(false);
          leave();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      channel.sink.add(jsonEncode({
        'type': asHost ? 'host' : 'join',
        'sessionId': sessionId,
      }));
    } catch (_) {
      if (!completer.isCompleted) completer.complete(false);
    }

    return completer.future
        .timeout(const Duration(seconds: 8), onTimeout: () => false);
  }

  void _onMessage(dynamic raw, Completer<bool> joinCompleter) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (msg['type']) {
      case 'joined':
        _sessionId = msg['sessionId'] as String?;
        _isHost = msg['role'] == 'host';
        if (!joinCompleter.isCompleted) joinCompleter.complete(true);
        break;
      case 'error':
        _errorController.add(msg['message']?.toString() ?? 'Erreur inconnue');
        if (!joinCompleter.isCompleted) joinCompleter.complete(false);
        break;
      case 'state':
        _stateController.add(JamStateMessage.fromJson(msg));
        break;
      case 'host_left':
        _hostLeftController.add(null);
        leave();
        break;
      case 'participant_count':
        _participantCountController.add(msg['count'] as int? ?? 0);
        break;
      case 'command':
        _commandController.add(JamCommandMessage(msg['action'] as String? ?? ''));
        break;
    }
  }

  void sendState({
    required String trackId,
    required int positionMs,
    required bool isPlaying,
    String? deviceName,
  }) {
    if (!_isHost || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'state',
      'trackId': trackId,
      'positionMs': positionMs,
      'isPlaying': isPlaying,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'deviceName': deviceName,
    }));
  }

  /// Envoie une commande de controle a distance vers l'hote (voir
  /// commandStream cote hote) -- reserve aux participants.
  void sendCommand(String action) {
    if (_isHost || _channel == null) return;
    _channel!.sink.add(jsonEncode({'type': 'command', 'action': action}));
  }

  Future<void> leave() async {
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    _sessionId = null;
    _isHost = false;
  }
}
