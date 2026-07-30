import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class VinlandAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;

  VinlandAudioHandler(this._player) {
    // Propagation de l'état du player vers la notification système
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Média en cours
    _player.durationStream.listen((duration) {
      final index = _player.currentIndex;
      if (index != null && index < queue.value.length) {
        final item = queue.value[index];
        mediaItem.add(item.copyWith(duration: duration));
      }
    });
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  /// Charge une liste de tracks et démarre la lecture
  Future<void> loadAndPlay(List<MediaItem> items, int startIndex) async {
    queue.add(items);

    final sources = items.map((item) {
      if (item.extras?['isAsset'] == true) {
        return AudioSource.asset(item.id);
      }
      return AudioSource.file(item.id);
    }).toList();

    await _player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: startIndex,
    );
    await _player.play();
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
