import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;

export 'package:just_audio/just_audio.dart' show LoopMode;

/// Un titre de la file, decrit sans dependre d'un backend audio precis
/// (just_audio ou media_kit interpretent chacun ce chemin/URL a leur facon).
class PlayerQueueItem {
  final String path;
  final bool isAsset;
  final bool isRemote;

  const PlayerQueueItem({
    required this.path,
    required this.isAsset,
    required this.isRemote,
  });
}

/// Abstraction commune entre just_audio (mobile/macOS/web, ou il fonctionne
/// nativement) et media_kit (desktop Windows/Linux, ou just_audio ne
/// declare aucune implementation). VinlandAudioHandler et AppState ne
/// parlent qu'a cette interface -- le choix du backend se fait une seule
/// fois, dans main.dart, selon la plateforme.
abstract class PlayerEngine {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<bool> get playingStream;
  Stream<int?> get currentIndexStream;

  /// Emet quand la file en cours arrive naturellement a sa fin (pas de
  /// boucle) -- equivalent de ProcessingState.completed chez just_audio.
  Stream<void> get completedStream;

  /// Messages d'erreur de lecture (reseau, decodage, ...), pour logging.
  Stream<String> get errorMessages;

  Duration get position;
  Duration? get duration;
  Duration get bufferedPosition;
  double get speed;
  double get volume;
  bool get playing;
  int? get currentIndex;

  /// Vrai si une file a deja ete chargee au moins une fois (permet de
  /// distinguer "en pause" de "rien a lire encore").
  bool get hasSource;

  bool get shuffleModeEnabled;
  LoopMode get loopMode;
  AudioProcessingState get processingState;

  Future<void> setAudioSources(
    List<PlayerQueueItem> items, {
    required int initialIndex,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> seekToNext();
  Future<void> seekToPrevious();
  Future<void> setShuffleModeEnabled(bool enabled);
  Future<void> setLoopMode(LoopMode mode);
  Future<void> dispose();
}
