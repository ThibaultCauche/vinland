import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../player_engine.dart';
import 'cast_channel.dart';
import 'cast_message.dart';

/// Lecture sur une Chromecast, vue comme un moteur audio de plus.
///
/// Lance le recepteur media par defaut de Google (pas d'appli a publier :
/// il lit une URL et affiche titre, artiste et pochette), lui donne l'URL
/// de stream Navidrome du titre et suit son etat. C'est donc la Chromecast
/// qui telecharge le titre : elle doit pouvoir joindre le serveur.
///
/// Comme les autres moteurs, il ne recoit qu'un titre a la fois (voir
/// PlayerController._playSingle) ; la fin du titre est remontee par
/// [completedStream] et la file avance cote Dart.
class CastPlayerEngine implements PlayerEngine {
  CastPlayerEngine._(this._channel, this._transportId, this._sessionId) {
    _sub = _channel.messages.listen(_onMessage);
    unawaited(_channel.done.then((_) => _end()));
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  /// Recepteur media par defaut de Google (Default Media Receiver).
  static const defaultReceiverAppId = 'CC1AD845';

  /// Ouvre le recepteur sur la Chromecast au bout de [channel].
  static Future<CastPlayerEngine> launch(CastChannel channel) async {
    channel.send(CastNamespace.connection, 'receiver-0', {'type': 'CONNECT'});
    final reply = await channel.request(
      CastNamespace.receiver,
      'receiver-0',
      {'type': 'LAUNCH', 'appId': defaultReceiverAppId},
    );
    final app = _receiverApp(reply.json);
    if (app == null) {
      throw StateError('La Chromecast a refuse de lancer le lecteur');
    }
    final transportId = app['transportId'] as String;
    channel.send(CastNamespace.connection, transportId, {'type': 'CONNECT'});
    final engine =
        CastPlayerEngine._(channel, transportId, app['sessionId'] as String?);
    engine._readVolume(reply.json);
    return engine;
  }

  static Map<String, dynamic>? _receiverApp(Map<String, dynamic>? payload) {
    if (payload?['type'] != 'RECEIVER_STATUS') return null;
    final apps = (payload?['status'] as Map?)?['applications'];
    if (apps is! List) return null;
    for (final app in apps) {
      if (app is Map<String, dynamic> &&
          app['appId'] == defaultReceiverAppId &&
          app['transportId'] is String) {
        return app;
      }
    }
    return null;
  }

  final CastChannel _channel;
  final String _transportId;
  final String? _sessionId;
  late final StreamSubscription<CastMessage> _sub;
  late final Timer _ticker;

  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration?>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _indexCtrl = StreamController<int?>.broadcast();
  final _completedCtrl = StreamController<void>.broadcast();
  final _errorsCtrl = StreamController<String>.broadcast();
  final _endedCtrl = StreamController<void>.broadcast();
  final _volumeCtrl = StreamController<double>.broadcast();

  int? _mediaSessionId;
  bool _playing = false;
  bool _hasSource = false;
  bool _loading = false;
  bool _ended = false;
  int? _finishedSession;

  /// Session media du titre charge en dernier : seule sa fin fait avancer
  /// la file (un etat en retard du titre precedent ne compte pas).
  int? _loadedSession;
  Duration _positionBase = Duration.zero;
  final _sinceStatus = Stopwatch();
  Duration? _duration;
  AudioProcessingState _state = AudioProcessingState.idle;
  double _deviceVolume = 1.0;
  bool _shuffle = false;
  LoopMode _loop = LoopMode.off;
  int _ticks = 0;

  /// La session s'est arretee sans nous : Chromecast eteinte, Wi-Fi perdu,
  /// ou quelqu'un d'autre a pris la main dessus.
  Stream<void> get ended => _endedCtrl.stream;
  bool get isEnded => _ended;

  /// Volume de la Chromecast (0..1), tel qu'elle le signale.
  double get deviceVolume => _deviceVolume;
  Stream<double> get deviceVolumeStream => _volumeCtrl.stream;

  // --- Messages de la Chromecast ------------------------------------------

  void _onMessage(CastMessage message) {
    final payload = message.json;
    if (payload == null) return;
    if (message.namespace == CastNamespace.connection &&
        message.sourceId == _transportId &&
        payload['type'] == 'CLOSE') {
      _end();
      return;
    }
    if (message.namespace == CastNamespace.receiver &&
        payload['type'] == 'RECEIVER_STATUS') {
      _readVolume(payload);
      // Notre lecteur n'est plus lance (autre appli ouverte sur la tele).
      final app = _receiverApp(payload);
      if (app == null ||
          (_sessionId != null && app['sessionId'] != _sessionId)) {
        _end();
      }
      return;
    }
    if (message.namespace != CastNamespace.media) return;
    switch (payload['type']) {
      case 'MEDIA_STATUS':
        final statuses = payload['status'];
        if (statuses is List && statuses.isNotEmpty) {
          final status = statuses.first;
          if (status is Map<String, dynamic>) _onMediaStatus(status);
        }
      case 'LOAD_FAILED' || 'LOAD_CANCELLED' || 'INVALID_REQUEST':
        _errorsCtrl.add('Chromecast : ${payload['type']}'
            '${payload['reason'] != null ? ' (${payload['reason']})' : ''}');
    }
  }

  void _readVolume(Map<String, dynamic>? payload) {
    final level = (((payload?['status'] as Map?)?['volume']) as Map?)?['level'];
    if (level is num && level.toDouble() != _deviceVolume) {
      _deviceVolume = level.toDouble().clamp(0.0, 1.0);
      _volumeCtrl.add(_deviceVolume);
    }
  }

  void _onMediaStatus(Map<String, dynamic> status) {
    final sessionId = status['mediaSessionId'];
    if (sessionId is int) _mediaSessionId = sessionId;
    final time = status['currentTime'];
    if (time is num) {
      _positionBase = Duration(milliseconds: (time * 1000).round());
      _sinceStatus
        ..reset()
        ..start();
    }
    final mediaDuration = (status['media'] as Map?)?['duration'];
    if (mediaDuration is num && mediaDuration > 0) {
      final d = Duration(milliseconds: (mediaDuration * 1000).round());
      if (d != _duration) {
        _duration = d;
        _durationCtrl.add(d);
      }
    }
    switch (status['playerState']) {
      case 'PLAYING':
        _state = AudioProcessingState.ready;
        _setPlaying(true);
      case 'PAUSED':
        _state = AudioProcessingState.ready;
        _setPlaying(false);
      case 'BUFFERING':
        _state = AudioProcessingState.buffering;
      case 'IDLE':
        _setPlaying(false);
        final reason = status['idleReason'];
        final current = sessionId is int && sessionId == _loadedSession;
        if (reason == 'FINISHED' && current && !_loading) {
          _state = AudioProcessingState.completed;
          if (_finishedSession != sessionId) {
            _finishedSession = sessionId;
            _completedCtrl.add(null);
          }
        } else if (reason == 'ERROR') {
          _state = AudioProcessingState.error;
          _errorsCtrl.add('La Chromecast n\'arrive pas a lire ce titre '
              '(serveur injoignable depuis la Chromecast ?)');
        } else if (!_loading && reason != 'FINISHED') {
          _state = AudioProcessingState.idle;
        }
    }
    _positionCtrl.add(position);
  }

  void _setPlaying(bool playing) {
    if (_playing == playing) return;
    _playing = playing;
    _playingCtrl.add(playing);
  }

  void _tick() {
    if (!_playing) return;
    _positionCtrl.add(position);
    // L'etat n'est envoye qu'aux changements : on recale la position de
    // temps en temps.
    if (++_ticks % 10 == 0) _media({'type': 'GET_STATUS'});
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _setPlaying(false);
    _endedCtrl.add(null);
  }

  void _media(Map<String, Object?> payload) {
    final id = _mediaSessionId;
    unawaited(_channel.request(CastNamespace.media, _transportId, {
      ...payload,
      if (id != null && payload['type'] != 'GET_STATUS') 'mediaSessionId': id,
    }).then((_) {}, onError: (Object _) {}));
  }

  // --- PlayerEngine -------------------------------------------------------

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;
  @override
  Stream<Duration?> get durationStream => _durationCtrl.stream;
  @override
  Stream<bool> get playingStream => _playingCtrl.stream;
  @override
  Stream<int?> get currentIndexStream => _indexCtrl.stream;
  @override
  Stream<void> get completedStream => _completedCtrl.stream;
  @override
  Stream<String> get errorMessages => _errorsCtrl.stream;

  @override
  Duration get position {
    if (!_playing) return _positionBase;
    final p = _positionBase + _sinceStatus.elapsed;
    final d = _duration;
    return d != null && p > d ? d : p;
  }

  @override
  Duration? get duration => _duration;
  @override
  Duration get bufferedPosition => position;
  @override
  double get speed => 1.0;
  @override
  double get volume => _deviceVolume;
  @override
  bool get playing => _playing;
  @override
  int? get currentIndex => _hasSource ? 0 : null;
  @override
  bool get hasSource => _hasSource;
  @override
  bool get shuffleModeEnabled => _shuffle;
  @override
  LoopMode get loopMode => _loop;
  @override
  AudioProcessingState get processingState => _state;

  @override
  Future<void> setAudioSources(
    List<PlayerQueueItem> items, {
    required int initialIndex,
  }) async {
    if (_ended) throw StateError('Diffusion terminee');
    final item = items[initialIndex];
    // Titre telecharge : la Chromecast ne voit pas les fichiers du
    // telephone, elle le lit depuis le serveur.
    final url = item.isRemote ? item.path : item.streamUrl;
    if (url == null) {
      throw StateError('Fichier local : la Chromecast ne peut pas le lire');
    }
    _loading = true;
    _state = AudioProcessingState.loading;
    _setPlaying(false);
    _positionBase = Duration.zero;
    _sinceStatus.reset();
    _duration = null;
    _durationCtrl.add(null);
    try {
      final reply = await _channel.request(CastNamespace.media, _transportId, {
        'type': 'LOAD',
        'autoplay': false,
        'currentTime': 0,
        'media': {
          'contentId': url,
          'streamType': 'BUFFERED',
          // Navidrome transcode la lecture en direct en mp3 (voir
          // NavidromeService.getStreamUrl).
          'contentType': 'audio/mpeg',
          'metadata': {
            'metadataType': 3, // MusicTrackMediaMetadata
            if (item.title != null) 'title': item.title,
            if (item.artist != null) 'artist': item.artist,
            if (item.album != null) 'albumName': item.album,
            if (_isWeb(item.artUri))
              'images': [
                {'url': item.artUri.toString()},
              ],
          },
        },
      });
      if (reply.type != 'MEDIA_STATUS') {
        throw StateError('La Chromecast a refuse le titre (${reply.type})');
      }
      final statuses = reply.json?['status'];
      final first =
          statuses is List && statuses.isNotEmpty ? statuses.first : null;
      final loaded = first is Map ? first['mediaSessionId'] : null;
      _loadedSession = loaded is int ? loaded : _mediaSessionId;
    } finally {
      _loading = false;
    }
    _hasSource = true;
    _finishedSession = null;
    _indexCtrl.add(0);
  }

  static bool _isWeb(Uri? uri) =>
      uri != null && (uri.isScheme('http') || uri.isScheme('https'));

  @override
  Future<void> play() async {
    if (_mediaSessionId == null) return;
    _sinceStatus
      ..reset()
      ..start();
    _setPlaying(true);
    _media({'type': 'PLAY'});
  }

  @override
  Future<void> pause() async {
    if (_mediaSessionId == null) return;
    _positionBase = position;
    _setPlaying(false);
    _media({'type': 'PAUSE'});
  }

  @override
  Future<void> stop() async {
    if (_mediaSessionId == null) return;
    _positionBase = position;
    _setPlaying(false);
    _media({'type': 'STOP'});
  }

  @override
  Future<void> seek(Duration position) async {
    if (_mediaSessionId == null) return;
    _positionBase = position;
    _sinceStatus.reset();
    if (_playing) _sinceStatus.start();
    _positionCtrl.add(position);
    _media({'type': 'SEEK', 'currentTime': position.inMilliseconds / 1000});
  }

  /// Volume de la Chromecast elle-meme (celui de la tele/l'enceinte).
  @override
  Future<void> setVolume(double volume) async {
    _deviceVolume = volume.clamp(0.0, 1.0);
    _volumeCtrl.add(_deviceVolume);
    unawaited(_channel.request(CastNamespace.receiver, 'receiver-0', {
      'type': 'SET_VOLUME',
      'volume': {'level': _deviceVolume},
    }).then((_) {}, onError: (Object _) {}));
  }

  /// Le rattrapage de vitesse du Jam n'a pas d'equivalent sur la Chromecast.
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> seekToNext() async {}
  @override
  Future<void> seekToPrevious() async {}
  @override
  Future<void> setShuffleModeEnabled(bool enabled) async => _shuffle = enabled;
  @override
  Future<void> setLoopMode(LoopMode mode) async => _loop = mode;

  /// Ferme la connexion ; [stopReceiver] arrete aussi le lecteur sur la tele.
  Future<void> disconnect({bool stopReceiver = true}) async {
    if (stopReceiver && !_ended && _sessionId != null) {
      try {
        await _channel.request(CastNamespace.receiver, 'receiver-0', {
          'type': 'STOP',
          'sessionId': _sessionId,
        }).timeout(const Duration(seconds: 2));
      } catch (_) {
        // Chromecast deja injoignable : rien a arreter.
      }
    }
    _end();
    _ticker.cancel();
    await _sub.cancel();
    await _channel.close();
  }

  @override
  Future<void> dispose() => disconnect();
}
