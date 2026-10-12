import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../domain/jam_sync.dart';
import 'navidrome_service.dart';

class JamStateMessage {
  final String trackId;
  final int positionMs;
  final bool isPlaying;

  /// Instant ou l'hote a lu [positionMs], en heure du relais (voir
  /// JamService.relayNowMs) : les horloges des deux appareils ne sont
  /// jamais reglees pareil, seule celle du relais leur est commune. Un hote
  /// d'avant la session 15 envoie son heure locale : on retombe alors sur
  /// l'ancienne approximation.
  final int ts;
  final String? deviceName;

  /// Ids de la file d'attente de l'hote, non-null seulement quand elle a
  /// change depuis le dernier envoi (voir JamController.broadcastState) --
  /// evite de rerepeter potentiellement des milliers d'ids a chaque
  /// battement de 5s. Permet au participant de refleter la vraie file de
  /// l'hote (voir JamController._applyJamState) plutot que sa propre file locale,
  /// jamais lue tant qu'on suit un hote.
  final List<String>? queueIds;

  const JamStateMessage({
    required this.trackId,
    required this.positionMs,
    required this.isPlaying,
    required this.ts,
    this.deviceName,
    this.queueIds,
  });

  factory JamStateMessage.fromJson(Map<String, dynamic> json) =>
      JamStateMessage(
        trackId: json['trackId'] as String,
        positionMs: json['positionMs'] as int,
        isPlaying: json['isPlaying'] as bool,
        ts: json['ts'] as int,
        deviceName: json['deviceName'] as String?,
        queueIds: (json['queueIds'] as List?)?.cast<String>(),
      );
}

/// Commande de controle a distance (play/pause/suivant/precedent/lecture
/// d'un titre precis/deplacement dans le titre -- action 'queue_add'/
/// 'play_next'/'play_track'/'seek' + trackId/positionMs), envoyee par un
/// participant et recue uniquement par l'hote -- voir sendCommand. Un
/// participant ne pilote jamais sa propre file d'attente ni son propre
/// moteur audio (rien n'est charge localement tant qu'on suit un hote, voir
/// JamController.interceptPlayTrack) : ce canal est le seul moyen pour lui
/// d'influencer ce qui va vraiment jouer.
class JamCommandMessage {
  final String action;
  final String? trackId;
  final int? positionMs;
  final String? deviceName;
  const JamCommandMessage(this.action,
      {this.trackId, this.positionMs, this.deviceName});
}

/// Connexion au relais Jam vue par JamController : une seule session a la
/// fois, hote ou participant. Interface pour que le controleur se teste
/// avec un faux relais en memoire (voir test/fakes/fake_jam_service.dart) ;
/// l'implementation de l'app est [WebSocketJamService].
abstract class JamService {
  String? get sessionId;
  bool get isHost;

  /// Vrai des que la connexion est ouverte, y compris le temps que le
  /// relais confirme host()/join().
  bool get isActive;

  /// Etat de l'hote, recu uniquement par les participants.
  Stream<JamStateMessage> get stateStream;
  Stream<void> get hostLeftStream;
  Stream<int> get participantCountStream;

  /// Pseudos des participants actuels (voir _Peer.username cote relais) --
  /// permet a l'hote de choisir a qui ceder l'hebergement (voir
  /// sendTransferHost). Emis en meme temps que participantCountStream.
  Stream<List<String>> get participantsStream;

  /// Commandes envoyees par les participants, recues uniquement par l'hote.
  Stream<JamCommandMessage> get commandStream;

  /// Emis quand ce peer change de role suite a un transfert d'hebergement
  /// (voir sendTransferHost) : true s'il vient de devenir hote, false s'il
  /// vient d'etre retrograde en participant. Ne concerne que les deux
  /// extremites du transfert -- les autres participants suivent simplement
  /// le nouvel hote sans rien remarquer.
  Stream<bool> get hostTransferredStream;

  /// Ecart mesure entre l'horloge locale et celle du relais (voir
  /// ClockEstimate), mis a jour apres chaque connexion puis regulierement.
  ClockEstimate get clock;

  /// Heure du relais estimee maintenant, en ms depuis l'epoch.
  int relayNowMs();

  String generateSessionId();

  /// SessionId stable de la synchro perso du compte (voir
  /// JamController.personalSessionId).
  String personalSessionId(String username);

  Future<bool> host(String sessionId);
  Future<bool> join(String sessionId);

  void sendState({
    required String trackId,
    required int positionMs,
    required bool isPlaying,
    String? deviceName,
    List<String>? queueIds,
  });

  void sendCommand(String action,
      {String? trackId, int? positionMs, String? deviceName});

  void sendTransferHost(String targetUsername);

  Future<void> leave();
}

/// Client du relais Jam (voir jam_relay/) : connexion WebSocket a un service
/// separe de Navidrome, expose sur le meme hostname Funnel sous /jam (voir
/// jam_relay/README.md). Modele hote-autoritaire : l'hote envoie son etat de
/// lecture via sendState(), les participants le recoivent via stateStream et
/// n'envoient jamais d'etat eux-memes.
class WebSocketJamService implements JamService {
  WebSocketJamService(this._navidrome);

  final NavidromeService _navidrome;

  /// Mesures par synchro d'horloge (voir _syncClock).
  static const clockSamples = 5;

  /// Les horloges derivent de quelques ms par minute, et le chemin reseau
  /// change (Wi-Fi -> 4G) : on remesure regulierement.
  static const clockRefresh = Duration(minutes: 1);

  ClockEstimate _clock = ClockEstimate.unknown;
  @override
  ClockEstimate get clock => _clock;

  @override
  int relayNowMs() => DateTime.now().millisecondsSinceEpoch + _clock.offsetMs;

  Timer? _clockTimer;
  int _nextPingId = 0;
  final Map<int, Completer<ClockSample?>> _pendingPings = {};

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? _sessionId;
  bool _isHost = false;

  @override
  String? get sessionId => _sessionId;
  @override
  bool get isHost => _isHost;
  @override
  bool get isActive => _channel != null;

  final _stateController = StreamController<JamStateMessage>.broadcast();
  @override
  Stream<JamStateMessage> get stateStream => _stateController.stream;

  final _hostLeftController = StreamController<void>.broadcast();
  @override
  Stream<void> get hostLeftStream => _hostLeftController.stream;

  final _participantCountController = StreamController<int>.broadcast();
  @override
  Stream<int> get participantCountStream => _participantCountController.stream;

  final _participantsController = StreamController<List<String>>.broadcast();
  @override
  Stream<List<String>> get participantsStream => _participantsController.stream;

  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  final _commandController = StreamController<JamCommandMessage>.broadcast();
  @override
  Stream<JamCommandMessage> get commandStream => _commandController.stream;

  final _hostTransferredController = StreamController<bool>.broadcast();
  @override
  Stream<bool> get hostTransferredStream => _hostTransferredController.stream;

  String? _relayUrl() {
    final baseUrl = _navidrome.baseUrl;
    if (baseUrl == null || baseUrl.isEmpty) return null;
    final wsBase = baseUrl
        .replaceFirst(RegExp(r'^https'), 'wss')
        .replaceFirst(RegExp(r'^http'), 'ws');
    return '$wsBase/jam';
  }

  @override
  String generateSessionId() {
    final random = Random.secure();
    final bytes = List.generate(6, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// SessionId stable et prive pour la synchro multi-appareils "perso" (voir
  /// JamController.onLocalTrackStarted/_tryJoinPersonalSync) : deterministe a
  /// partir du compte Navidrome, pour que tous les appareils du meme compte
  /// se retrouvent automatiquement sans code a partager. Hashe (avec un sel
  /// fixe) plutot qu'utilise tel quel pour ne pas exposer le nom d'utilisateur
  /// Navidrome en clair a qui intercepterait ce sessionId.
  @override
  String personalSessionId(String username) {
    final digest = sha256.convert(utf8.encode('vinland_personal_$username'));
    return digest.toString().substring(0, 24);
  }

  @override
  Future<bool> host(String sessionId) => _connect(sessionId, asHost: true);

  @override
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
        'username': _navidrome.username,
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
        _startClockSync();
        break;
      case 'pong':
        final pending = _pendingPings.remove(msg['id']);
        final sent = msg['t0'];
        final relay = msg['relayTs'];
        if (pending != null && sent is int && relay is int) {
          pending.complete(ClockSample(
            sentMs: sent,
            relayMs: relay,
            receivedMs: DateTime.now().millisecondsSinceEpoch,
          ));
        }
        break;
      case 'error':
        _errorController.add(msg['message']?.toString() ?? 'Erreur inconnue');
        if (!joinCompleter.isCompleted) joinCompleter.complete(false);
        // Sans ca, _channel restait ouvert malgre l'echec (ex: join() sur
        // la session "perso" antes qu'aucun appareil ne l'ait hebergee --
        // le cas d'un compte teste sur un seul appareil) : isActive
        // continuait de rapporter true bien que ni host() ni join() n'aient
        // reellement abouti, ce qui faisait passer le Jam en mode "suivi
        // passif" et bloquait silencieusement playTrack/togglePlayPause/
        // nextTrack/previousTrack (retour testeur : plus aucun bouton ne
        // repondait, seule la navigation via la file d'attente restait
        // possible car playFromQueue n'a pas cette garde).
        leave();
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
        final usernames = (msg['usernames'] as List?)?.cast<String>();
        if (usernames != null) _participantsController.add(usernames);
        break;
      case 'command':
        _commandController.add(JamCommandMessage(
          msg['action'] as String? ?? '',
          trackId: msg['trackId'] as String?,
          positionMs: msg['positionMs'] as int?,
          deviceName: msg['deviceName'] as String?,
        ));
        break;
      case 'host_transferred':
        _isHost = msg['role'] == 'host';
        _hostTransferredController.add(_isHost);
        break;
    }
  }

  @override
  void sendState({
    required String trackId,
    required int positionMs,
    required bool isPlaying,
    String? deviceName,
    List<String>? queueIds,
  }) {
    if (!_isHost || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'state',
      'trackId': trackId,
      'positionMs': positionMs,
      'isPlaying': isPlaying,
      'ts': relayNowMs(),
      'deviceName': deviceName,
      if (queueIds != null) 'queueIds': queueIds,
    }));
  }

  /// Envoie une commande de controle a distance vers l'hote (voir
  /// commandStream cote hote) -- reserve aux participants.
  @override
  void sendCommand(String action,
      {String? trackId, int? positionMs, String? deviceName}) {
    if (_isHost || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'command',
      'action': action,
      if (trackId != null) 'trackId': trackId,
      if (positionMs != null) 'positionMs': positionMs,
      if (deviceName != null) 'deviceName': deviceName,
    }));
  }

  /// Cede l'hebergement a un participant nomme (voir participantsStream
  /// pour la liste des pseudos disponibles) -- reserve a l'hote actuel.
  /// Les deux extremites sont notifiees via hostTransferredStream ; les
  /// autres participants ne voient que le prochain 'state' venir d'ailleurs.
  @override
  void sendTransferHost(String targetUsername) {
    if (!_isHost || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'transfer_host',
      'targetUsername': targetUsername,
    }));
  }

  // --- Horloge commune -------------------------------------------------

  void _startClockSync() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(clockRefresh, (_) => unawaited(_syncClock()));
    unawaited(_syncClock());
  }

  /// Echange [clockSamples] ping/pong avec le relais, l'un apres l'autre
  /// (des pings simultanes se gêneraient dans la meme file d'envoi). Un
  /// relais d'avant la session 15 ne repond pas : l'estimation reste
  /// inconnue (ecart 0), comme avant.
  Future<void> _syncClock() async {
    final samples = <ClockSample>[];
    for (var i = 0; i < clockSamples; i++) {
      final channel = _channel;
      if (channel == null) return;
      final id = _nextPingId++;
      final pending = Completer<ClockSample?>();
      _pendingPings[id] = pending;
      channel.sink.add(jsonEncode({
        'type': 'ping',
        'id': id,
        't0': DateTime.now().millisecondsSinceEpoch,
      }));
      final sample = await pending.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      _pendingPings.remove(id);
      if (sample == null) break;
      samples.add(sample);
    }
    if (samples.isNotEmpty && _channel != null) {
      _clock = ClockEstimate.fromSamples(samples);
    }
  }

  @override
  Future<void> leave() async {
    _clockTimer?.cancel();
    _clockTimer = null;
    for (final pending in _pendingPings.values) {
      if (!pending.isCompleted) pending.complete(null);
    }
    _pendingPings.clear();
    _clock = ClockEstimate.unknown;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    _sessionId = null;
    _isHost = false;
  }
}
