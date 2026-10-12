import '../models/track.dart';

/// Ce que le Jam a le droit de faire sur la lecture locale (voir
/// JamController). Implemente par PlayerController : c'est le Jam qui pilote
/// le lecteur, jamais l'inverse -- le lecteur ne sait pas qu'un Jam existe.
abstract class JamPlayback {
  Track? get currentTrack;
  bool get isPlaying;
  Duration get position;

  /// Titres a venir, diffuses aux participants par l'hote.
  List<Track> get queue;

  Future<void> playTrack(Track track, {List<Track>? trackList});

  /// Voir PlayerController.togglePlayPause pour le sens du booleen renvoye.
  bool togglePlayPause();
  Future<void> next();
  Future<void> previous();
  void seek(Duration pos);
  void addToQueue(Track track);
  void playNext(Track track);

  /// Remplace la file par celle de l'hote suivi.
  void replaceQueue(List<Track> tracks);

  /// Aligne lecture/pause sur l'hote suivi, sans compter comme une action
  /// manuelle (contrairement a togglePlayPause).
  Future<void> setPlaying(bool playing);
}
