import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class VinlandAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  AudioPlayer get player => _player;

  VinlandAudioHandler(this._player) {
    // Propagation de l'état playback vers la notification système
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Met à jour mediaItem quand la track change (next/previous/auto)
    _player.currentIndexStream.listen((index) {
      _updateMediaItemFromIndex(index);
    });

    // Met à jour la duration quand elle est connue
    _player.durationStream.listen((duration) {
      final index = _player.currentIndex;
      if (index != null && index >= 0 && index < queue.value.length) {
        final item = queue.value[index];
        mediaItem.add(MediaItem(
          id: item.id,
          title: item.title,
          artist: item.artist,
          album: item.album,
          duration: duration,
          artUri: item.artUri,
          extras: item.extras,
        ));
      }
    });
  }

  void _updateMediaItemFromIndex(int? index) {
    if (index == null || index < 0 || index >= queue.value.length) return;
    final item = queue.value[index];
    mediaItem.add(item);
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

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  /// Charge une liste de tracks et démarre la lecture
  Future<void> loadAndPlay(List<MediaItem> items, int startIndex) async {
    queue.add(items);

    // Initialise immédiatement le mediaItem pour que la notification apparaisse
    if (startIndex >= 0 && startIndex < items.length) {
      mediaItem.add(items[startIndex]);
    }

    final sources = items.map((item) {
      final isAsset = item.extras?['isAsset'] == true;
      final isRemote = item.id.startsWith('http');

      if (isAsset) {
        return AudioSource.asset(item.id);
      } else if (isRemote) {
        return AudioSource.uri(Uri.parse(item.id));
      } else {
        return AudioSource.file(item.id);
      }
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
