import '../models/track.dart';

/// Regles de l'ecoute hors-ligne, sans Flutter ni disque (voir
/// test/domain/offline_playback_test.dart).

/// Un titre est jouable sans le NAS s'il a ete telecharge, ou s'il ne vient
/// pas du NAS du tout (fichier local).
bool isPlayableWithoutServer(Track track, {required bool downloaded}) =>
    downloaded || track.subsonicId == null;

/// Le titre a lancer quand on tape [tapped] dans [list] alors que seuls
/// certains titres sont jouables : lui-meme s'il l'est, sinon le premier
/// jouable qui le suit (en revenant au debut de la liste). Null si aucun
/// titre de la liste n'est jouable.
Track? firstPlayableFrom(
  Track tapped,
  List<Track> list,
  bool Function(Track track) isPlayable,
) {
  if (isPlayable(tapped)) return tapped;
  if (list.isEmpty) return null;
  final start = list.indexWhere((t) => t.id == tapped.id);
  for (var i = 1; i <= list.length; i++) {
    final candidate = list[(start + i) % list.length];
    if (isPlayable(candidate)) return candidate;
  }
  return null;
}

/// Collections (album, playlist, titres likes) dont le telechargement est
/// suivi : leurs nouveaux titres sont telecharges a chaque synchro.
class OfflineCollection {
  OfflineCollection._();

  static const liked = 'liked';
  static String album(String id) => 'album:$id';
  static String playlist(String id) => 'playlist:$id';

  static bool isAlbum(String key) => key.startsWith('album:');
  static bool isPlaylist(String key) => key.startsWith('playlist:');

  /// Id de l'album ou de la playlist porte par [key].
  static String idOf(String key) => key.substring(key.indexOf(':') + 1);
}

/// Taille lisible ("850 Mo", "1,2 Go").
String formatBytes(int bytes) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  if (bytes >= gb) {
    return '${(bytes / gb).toStringAsFixed(1).replaceAll('.', ',')} Go';
  }
  if (bytes >= mb) return '${(bytes / mb).round()} Mo';
  if (bytes > 0) return '${(bytes / 1024).ceil()} Ko';
  return '0 Mo';
}
