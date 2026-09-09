import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'player_engine.dart';

class VinlandAudioHandler extends BaseAudioHandler with SeekHandler {
  final PlayerEngine _engine;
  PlayerEngine get player => _engine;

  final _customActionController = StreamController<String>.broadcast();
  Stream<String> get customActionStream => _customActionController.stream;

  VinlandAudioHandler(this._engine) {
    // Le PlaybackState remonte a audio_service (notification/lock screen
    // Android) est recalcule a chaque changement pertinent -- generique,
    // ne depend plus du backend (just_audio ou media_kit).
    _engine.positionStream.listen(
      (_) => _pushState(),
      onError: (Object e, StackTrace st) {
        // Une erreur reseau/decodage ponctuelle ne doit pas remonter
        // non-geree et faire planter l'app : on la journalise seulement.
        print('PLAYBACK EVENT ERROR: $e');
      },
    );
    _engine.playingStream.listen((_) => _pushState());
    _engine.currentIndexStream.listen((index) {
      _updateMediaItemFromIndex(index);
      _pushState();
    });

    _engine.errorMessages.listen((msg) {
      print('AUDIO ERROR: $msg');
    });

    _engine.durationStream.listen((duration) {
      final index = _engine.currentIndex;
      if (duration != null &&
          index != null &&
          index >= 0 &&
          index < queue.value.length) {
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

  void _pushState() {
    try {
      playbackState.add(_transformState());
    } catch (e) {
      print('PLAYBACK STATE PUSH ERROR: $e');
    }
  }

  void _updateMediaItemFromIndex(int? index) {
    if (index == null || index < 0 || index >= queue.value.length) return;
    final item = queue.value[index];
    mediaItem.add(item);
  }

  @override
  Future<void> play() => _engine.play();
  @override
  Future<void> pause() => _engine.pause();
  @override
  Future<void> seek(Duration position) => _engine.seek(position);
  @override
  Future<void> skipToNext() => _engine.seekToNext();
  @override
  Future<void> skipToPrevious() => _engine.seekToPrevious();

  @override
  Future<void> stop() async {
    await _engine.stop();
    await super.stop();
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    _customActionController.add(name);
  }

  Future<void> loadAndPlay(List<MediaItem> items, int startIndex) async {
    queue.add(items);
    if (startIndex >= 0 && startIndex < items.length) {
      mediaItem.add(items[startIndex]);
    }

    final sources = items.map((item) {
      final isAsset = item.extras?['isAsset'] == true;
      final isRemote = item.id.startsWith('http');
      print(
          '🎵 AUDIO SOURCE: id=${item.id.substring(0, item.id.length > 60 ? 60 : item.id.length)}... isAsset=$isAsset isRemote=$isRemote');
      return PlayerQueueItem(path: item.id, isAsset: isAsset, isRemote: isRemote);
    }).toList();

    try {
      await _engine.setAudioSources(sources, initialIndex: startIndex);
      print('✅ AudioSource chargé, lecture...');
      await _engine.play();
    } catch (e) {
      print('❌ ERREUR LECTURE: $e');
    }
  }

  PlaybackState _transformState() {
    return PlaybackState(
      controls: [
        MediaControl(
          androidIcon: 'drawable/ic_notification_add',
          label: 'Ajouter aux favoris',
          action: MediaAction.custom,
          customAction: CustomMediaAction(name: 'add_to_likes'),
        ),
        MediaControl.skipToPrevious,
        if (_engine.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [1, 2, 3],
      processingState: _engine.processingState,
      playing: _engine.playing,
      updatePosition: _engine.position,
      bufferedPosition: _engine.bufferedPosition,
      speed: _engine.speed,
      queueIndex: _engine.currentIndex,
    );
  }

  Future<void> updateNotificationColor(int color) async {
    final current = mediaItem.value;
    if (current == null) return;
    mediaItem.add(current.copyWith(
      extras: {
        ...?current.extras,
        'androidNotificationColor': color,
      },
    ));
  }

  Future<void> toggleShuffle() async {
    await _engine.setShuffleModeEnabled(!_engine.shuffleModeEnabled);
  }

  bool get isShuffled => _engine.shuffleModeEnabled;

  Future<void> setLoopMode(LoopMode mode) async {
    await _engine.setLoopMode(mode);
  }

  LoopMode get loopMode => _engine.loopMode;
}
