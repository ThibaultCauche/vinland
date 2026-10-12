import 'dart:async';
import 'dart:collection';

import 'package:audio_service/audio_service.dart';
import 'package:vinland/data/track_repository.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/player_engine.dart';

/// Faux moteur audio : les evenements (position, lecture, fin de titre)
/// sont emis a la main par le test, de facon synchrone, pour rejouer
/// exactement les sequences vues sur de vrais appareils.
class FakePlayerEngine implements PlayerEngine {
  final _position = StreamController<Duration>.broadcast(sync: true);
  final _duration = StreamController<Duration?>.broadcast(sync: true);
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _index = StreamController<int?>.broadcast(sync: true);
  final _completed = StreamController<void>.broadcast(sync: true);
  final _errors = StreamController<String>.broadcast(sync: true);

  @override
  bool hasSource = false;
  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration? duration;

  void emitPosition(Duration pos) {
    position = pos;
    _position.add(pos);
  }

  void emitDuration(Duration? d) {
    duration = d;
    _duration.add(d);
  }

  void emitPlaying(bool value) {
    playing = value;
    _playing.add(value);
  }

  void emitIndex(int? index) => _index.add(index);
  void emitCompleted() => _completed.add(null);

  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<int?> get currentIndexStream => _index.stream;
  @override
  Stream<void> get completedStream => _completed.stream;
  @override
  Stream<String> get errorMessages => _errors.stream;

  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  double get speed => 1;
  @override
  double volume = 1;
  @override
  int? get currentIndex => hasSource ? 0 : null;
  @override
  bool get shuffleModeEnabled => false;
  @override
  LoopMode get loopMode => LoopMode.off;
  @override
  AudioProcessingState get processingState => AudioProcessingState.ready;

  /// Journal des ordres recus (load:<chemin>, play, pause, stop), pour
  /// verifier ce que fait DeckPlayerEngine de chaque platine.
  final List<String> log = [];

  /// Chargement a faire attendre (reseau lent) : complete par le test.
  Completer<void>? pendingLoad;
  bool loadThrows = false;

  @override
  Future<void> setAudioSources(List<PlayerQueueItem> items,
      {required int initialIndex}) async {
    log.add('load:${items[initialIndex].path}');
    final pending = pendingLoad;
    if (pending != null) {
      pendingLoad = null;
      await pending.future;
    }
    if (loadThrows) throw StateError('flux injoignable');
    hasSource = true;
  }

  @override
  Future<void> play() async {
    log.add('play');
    emitPlaying(true);
  }

  @override
  Future<void> pause() async {
    log.add('pause');
    emitPlaying(false);
  }

  @override
  Future<void> stop() async {
    log.add('stop');
    if (playing) emitPlaying(false);
  }

  @override
  Future<void> seek(Duration position) async {
    this.position = position;
  }

  @override
  Future<void> setVolume(double volume) async => this.volume = volume;
  @override
  Future<void> seekToNext() async {}
  @override
  Future<void> seekToPrevious() async {}
  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}
  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> dispose() async {}
}

/// Faux VinlandAudioHandler : note tout ce qui lui est demande, et laisse le
/// test decider si un chargement reussit (par titre, ou en le faisant
/// attendre via un Completer pour simuler un NAS lent).
class FakePlaybackOutput implements PlaybackOutput {
  FakePlaybackOutput([FakePlayerEngine? engine])
      : engine = engine ?? FakePlayerEngine();

  final FakePlayerEngine engine;

  /// Titres (MediaItem.title) dont le chargement echoue.
  final Set<String> failingTitles = {};

  /// Chargements a faire attendre, dans l'ordre des appels.
  final Queue<Completer<bool>> pendingLoads = Queue();

  final List<String> loadedTitles = [];
  final List<String> calls = [];
  bool stopThrows = false;

  @override
  PlayerEngine get player => engine;

  /// Fondu demande a chaque chargement (dans l'ordre de loadedTitles).
  final List<Duration> crossfades = [];

  /// Gain ReplayGain demande a chaque chargement.
  final List<double> gains = [];

  /// Titres dont le prechargement a ete demande, et ceux annules.
  final List<String> preloaded = [];
  int preloadCancels = 0;
  final List<double> trackGainChanges = [];

  /// Prechargement qui echoue (moteur simple, flux injoignable).
  bool preloadFails = false;

  @override
  Future<bool> preload(MediaItem item, {double gain = 1.0}) async {
    preloaded.add(item.title);
    return !preloadFails;
  }

  @override
  void cancelPreload() => preloadCancels++;

  @override
  Future<void> setTrackGain(double gain) async => trackGainChanges.add(gain);

  @override
  Future<bool> loadAndPlay(
    List<MediaItem> items,
    int startIndex, {
    Duration crossfade = Duration.zero,
    double gain = 1.0,
  }) async {
    final title = items[startIndex].title;
    loadedTitles.add(title);
    crossfades.add(crossfade);
    gains.add(gain);
    if (pendingLoads.isNotEmpty) {
      final ok = await pendingLoads.removeFirst().future;
      if (ok) engine.hasSource = true;
      return ok;
    }
    if (failingTitles.contains(title)) return false;
    engine.hasSource = true;
    return true;
  }

  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> seek(Duration position) async => calls.add('seek:$position');
  @override
  Future<void> stop() async {
    calls.add('stop');
    if (stopThrows) throw StateError('service audio mort');
  }
}

class FakeTrackRepository implements TrackRepository {
  FakeTrackRepository(Iterable<Track> tracks)
      : _byId = {for (final t in tracks) t.id: t};

  final Map<String, Track> _byId;
  final Map<String, String> offline = {};
  final List<String> playsRecorded = [];

  @override
  Track? findById(String id) => _byId[id];

  @override
  String? offlinePath(String trackId) => offline[trackId];

  @override
  Future<void> recordPlay(String trackId) async => playsRecorded.add(trackId);
}

Track fakeTrack(String id, {Duration duration = const Duration(minutes: 3)}) =>
    Track(
      id: id,
      title: id,
      artist: 'Artiste',
      album: 'Album',
      duration: duration,
      filePath: '/musique/$id.mp3',
    );
