import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'player_engine.dart';

/// Backend just_audio : utilise sur mobile/macOS/web, la ou just_audio
/// declare une vraie implementation native.
class JustAudioPlayerEngine implements PlayerEngine {
  final ja.AudioPlayer _player;

  JustAudioPlayerEngine(this._player);

  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<Duration?> get durationStream => _player.durationStream;
  @override
  Stream<bool> get playingStream =>
      _player.playerStateStream.map((s) => s.playing);
  @override
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  @override
  Stream<void> get completedStream => _player.processingStateStream
      .where((s) => s == ja.ProcessingState.completed);
  @override
  Stream<String> get errorMessages =>
      _player.errorStream.map((e) => 'code=${e.code} ${e.message}');

  @override
  Duration get position => _player.position;
  @override
  Duration? get duration => _player.duration;
  @override
  Duration get bufferedPosition => _player.bufferedPosition;
  @override
  double get speed => _player.speed;
  @override
  double get volume => _player.volume;
  @override
  bool get playing => _player.playing;
  @override
  int? get currentIndex => _player.currentIndex;
  @override
  bool get hasSource => _player.audioSource != null;
  @override
  bool get shuffleModeEnabled => _player.shuffleModeEnabled;
  @override
  LoopMode get loopMode => _player.loopMode;
  @override
  AudioProcessingState get processingState => const {
        ja.ProcessingState.idle: AudioProcessingState.idle,
        ja.ProcessingState.loading: AudioProcessingState.loading,
        ja.ProcessingState.buffering: AudioProcessingState.buffering,
        ja.ProcessingState.ready: AudioProcessingState.ready,
        ja.ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!;

  @override
  Future<void> setAudioSources(
    List<PlayerQueueItem> items, {
    required int initialIndex,
  }) async {
    final sources = items.map((item) {
      if (item.isAsset) return ja.AudioSource.asset(item.path.replaceFirst('assets/', ''));
      if (item.isRemote) return ja.AudioSource.uri(Uri.parse(item.path));
      return ja.AudioSource.file(item.path);
    }).toList();

    try {
      await _player.stop();
    } catch (_) {}
    await _player.setAudioSource(
      ja.ConcatenatingAudioSource(children: sources),
      initialIndex: initialIndex,
    );
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Future<void> seekToNext() => _player.seekToNext();
  @override
  Future<void> seekToPrevious() => _player.seekToPrevious();
  @override
  Future<void> setShuffleModeEnabled(bool enabled) =>
      _player.setShuffleModeEnabled(enabled);
  @override
  Future<void> setLoopMode(LoopMode mode) => _player.setLoopMode(mode);
  @override
  Future<void> dispose() => _player.dispose();
}
