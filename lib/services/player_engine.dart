import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;

export 'package:just_audio/just_audio.dart' show LoopMode;

/// Un titre de la file, decrit sans dependre d'un backend audio precis
/// (just_audio ou media_kit interpretent chacun ce chemin/URL a leur facon).
class PlayerQueueItem {
  final String path;
  final bool isRemote;

  const PlayerQueueItem({
    required this.path,
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

/// Ce que PlayerController pilote : le moteur (pour ses flux d'etat) et le
/// chargement d'un titre avec sa fiche pour la notification/l'ecran
/// verrouille. Implemente par VinlandAudioHandler, remplace par un faux
/// dans les tests (voir test/fakes/fake_player_engine.dart).
abstract class PlaybackOutput {
  PlayerEngine get player;

  /// Retourne false si le chargement echoue apres toutes les tentatives.
  ///
  /// Si le titre a ete precharge ([preload]), bascule simplement dessus,
  /// en fondu de [crossfade] si > 0. [gain] : volume ReplayGain du titre
  /// (0..1), multiplie par le volume choisi par l'utilisateur.
  Future<bool> loadAndPlay(
    List<MediaItem> items,
    int startIndex, {
    Duration crossfade = Duration.zero,
    double gain = 1.0,
  });

  /// Prepare le titre suivant sans interrompre celui qui joue. Retourne
  /// false si le moteur ne sait pas precharger ou si le chargement echoue :
  /// le titre sera alors charge normalement par [loadAndPlay].
  Future<bool> preload(MediaItem item, {double gain = 1.0});

  /// Le titre precharge n'est plus le suivant (file modifiee).
  void cancelPreload();

  /// Change le gain ReplayGain du titre en cours (reglage modifie).
  Future<void> setTrackGain(double gain);

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
}
