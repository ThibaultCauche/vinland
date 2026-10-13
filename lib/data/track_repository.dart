import '../models/track.dart';
import '../services/music_service.dart';

/// Ce dont la lecture a besoin de la bibliotheque, et rien de plus : de quoi
/// retrouver un titre, savoir s'il est telecharge et noter une ecoute.
/// Permet de tester PlayerController sans MusicService (cache disque, NAS).
abstract class TrackRepository {
  Track? findById(String id);

  /// Chemin du fichier telecharge pour l'ecoute hors ligne, ou null.
  String? offlinePath(String trackId);

  Future<void> recordPlay(String trackId);
}

class MusicServiceTrackRepository implements TrackRepository {
  MusicServiceTrackRepository(this._music);

  final MusicService _music;

  @override
  Track? findById(String id) {
    for (final t in _music.allTracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  String? offlinePath(String trackId) => _music.getOfflinePath(trackId);

  @override
  Future<void> recordPlay(String trackId) => _music.recordPlay(trackId);
}
