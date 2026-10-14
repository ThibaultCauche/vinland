import 'dart:async';

import 'package:audio_service/audio_service.dart';

import 'player_engine.dart';

/// Le moteur vu par toute l'app, qui joue soit sur l'appareil ([local]),
/// soit ailleurs (une Chromecast, voir CastPlayerEngine).
///
/// PlayerController et VinlandAudioHandler s'abonnent une fois pour toutes
/// aux flux du moteur : celui-ci les garde et relaie ceux du moteur actif,
/// comme DeckPlayerEngine le fait pour ses platines. Le passage d'un moteur
/// a l'autre (reprise du titre et de la position) se fait dans
/// VinlandAudioHandler.switchOutput.
class RoutedPlayerEngine implements PlayerEngine {
  RoutedPlayerEngine(this.local) : _active = local {
    _attach(local);
  }

  final PlayerEngine local;
  PlayerEngine _active;
  PlayerEngine get active => _active;
  bool get isLocal => identical(_active, local);

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _index = StreamController<int?>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];

  void _attach(PlayerEngine engine) {
    void forward<T>(Stream<T> source, StreamController<T> target) {
      _subs.add(source.listen(
        target.add,
        onError: (Object e, StackTrace st) => target.addError(e, st),
      ));
    }

    forward(engine.positionStream, _position);
    forward(engine.durationStream, _duration);
    forward(engine.playingStream, _playing);
    forward(engine.currentIndexStream, _index);
    forward(engine.completedStream, _completed);
    forward(engine.errorMessages, _errors);
  }

  /// Fait de [engine] le moteur actif. N'arrete ni ne charge rien : seuls
  /// les flux changent de source, avec l'etat du nouveau moteur pour que
  /// l'affichage suive tout de suite.
  void route(PlayerEngine engine) {
    if (identical(engine, _active)) return;
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    _active = engine;
    _attach(engine);
    _playing.add(engine.playing);
    _position.add(engine.position);
    _duration.add(engine.duration);
    _index.add(engine.currentIndex);
  }

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
  Duration get position => _active.position;
  @override
  Duration? get duration => _active.duration;
  @override
  Duration get bufferedPosition => _active.bufferedPosition;
  @override
  double get speed => _active.speed;
  @override
  double get volume => _active.volume;
  @override
  bool get playing => _active.playing;
  @override
  int? get currentIndex => _active.currentIndex;
  @override
  bool get hasSource => _active.hasSource;
  @override
  bool get shuffleModeEnabled => _active.shuffleModeEnabled;
  @override
  LoopMode get loopMode => _active.loopMode;
  @override
  AudioProcessingState get processingState => _active.processingState;

  @override
  Future<void> setAudioSources(
    List<PlayerQueueItem> items, {
    required int initialIndex,
  }) =>
      _active.setAudioSources(items, initialIndex: initialIndex);
  @override
  Future<void> play() => _active.play();
  @override
  Future<void> pause() => _active.pause();
  @override
  Future<void> stop() => _active.stop();
  @override
  Future<void> seek(Duration position) => _active.seek(position);
  @override
  Future<void> setVolume(double volume) => _active.setVolume(volume);
  @override
  Future<void> setSpeed(double speed) => _active.setSpeed(speed);
  @override
  Future<void> seekToNext() => _active.seekToNext();
  @override
  Future<void> seekToPrevious() => _active.seekToPrevious();
  @override
  Future<void> setShuffleModeEnabled(bool enabled) =>
      _active.setShuffleModeEnabled(enabled);
  @override
  Future<void> setLoopMode(LoopMode mode) => _active.setLoopMode(mode);

  @override
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    if (!isLocal) await _active.dispose();
    await local.dispose();
  }
}

/// Ce que CastController pilote pour passer la lecture d'un moteur a
/// l'autre. Implemente par VinlandAudioHandler.
abstract class OutputSwitch {
  /// Le moteur de l'appareil.
  PlayerEngine get localEngine;
  PlayerEngine get activeEngine;

  /// Passe la lecture sur [target] en reprenant le titre en cours a la meme
  /// position ; il ne repart en lecture que si [resume] et s'il jouait.
  Future<void> switchOutput(PlayerEngine target, {bool resume = true});
}
