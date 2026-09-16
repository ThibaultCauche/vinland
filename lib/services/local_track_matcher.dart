import '../models/discovered_track.dart';
import '../models/track.dart';

/// Cherche le titre local (NAS) correspondant a un titre decouvert (Deezer),
/// par artiste+titre+album approximatifs. Partagee entre desktop
/// (DesktopDiscoveredAlbumView) et mobile (DiscoveredAlbumScreen) -- avant
/// cette extraction, chacun avait sa propre copie et le meme bug ("Inconnu"
/// Deezer bloquant tout match sur l'artiste) avait ete corrige sur l'une
/// sans l'autre, faisant revenir le bug cote mobile (retour utilisateur).
/// Fonction pure top-level plutot qu'une methode de State, pour rester
/// testable sans contexte Flutter -- voir test/local_track_matcher_test.dart.
Track? findLocalTrackMatch(DiscoveredTrack dt, List<Track> localTracks) {
  String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Un champ vide (tag manquant en local) ne doit jamais "matcher" via
  // contains('') -- en Dart toute chaine contient la chaine vide.
  bool looseMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return a == b;
    return a == b || a.contains(b) || b.contains(a);
  }

  // dt.artistName == 'Inconnu' : Deezer n'a pas fourni d'artiste pour ce
  // titre precis (retour utilisateur : ces albums-la n'avaient jamais
  // d'options -- "..." absent, artiste affiche "Inconnu" -- meme quand le
  // titre etait reellement present sur le NAS). Sans ce cas particulier,
  // artistMatch exigeait que l'artiste LOCAL s'appelle litteralement
  // "Inconnu" lui aussi pour matcher -- ce qui n'arrive jamais en pratique,
  // donc le matching echouait systematiquement pour ces titres. Meme
  // traitement que dtAlbum ci-dessous, qui a deja ce garde-fou.
  final dtArtistUnknown = dt.artistName == 'Inconnu';
  final dtArtist = norm(dt.artistName);
  final dtTitle = norm(dt.title);
  final dtAlbum = dt.albumName == 'Inconnu' ? null : norm(dt.albumName);

  for (final lt in localTracks) {
    final artistMatch =
        dtArtistUnknown || looseMatch(norm(lt.artist), dtArtist);
    // Egalite stricte pour le titre, pas de contains() (conflit sinon entre
    // "Around the World" et ses propres variantes "(Radio Edit)"/"(Motorbass
    // Vice Mix)").
    final titleMatch = norm(lt.title) == dtTitle;
    final albumMatch = dtAlbum == null || looseMatch(norm(lt.album), dtAlbum);

    if (artistMatch && titleMatch && albumMatch) return lt;
  }
  return null;
}
