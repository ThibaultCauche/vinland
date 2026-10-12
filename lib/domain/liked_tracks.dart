import '../models/track.dart';

/// `liked` plus un titre "fantome" par entree de `missing` (titre importe
/// via CSV mais introuvable sur le NAS), intercale au bon endroit grace a la
/// meme date synthetique que celle posee sur les titres retrouves au moment
/// de l'import (voir StreamingMatchScreen._likeMatched) -- l'ordre affiche
/// correspond ainsi a l'ordre du fichier importe, pistes manquantes
/// comprises. Pour l'affichage seulement : ces titres fantomes n'ont pas de
/// fichier reel et doivent etre exclus de toute file de lecture.
List<Track> likedWithMissing(
    List<Track> liked, List<Map<String, dynamic>> missing) {
  final placeholders = missing.map((m) {
    return Track(
      id: 'missing:${m['title']}:${m['artist']}:${m['album']}',
      title: (m['title'] ?? '').toString(),
      artist: (m['artist'] ?? '').toString(),
      album: (m['album'] ?? '').toString(),
      duration: Duration.zero,
      isLiked: true,
      dateAdded: DateTime.tryParse((m['dateAdded'] ?? '').toString()),
    );
  }).toList();

  final combined = [...liked, ...placeholders];
  // Tiebreak sur l'ordre d'origine (index dans combined, deja stable cote
  // liked) en plus de la date : sans ca, un deuxieme List.sort avec des
  // ex-aequo (meme date, ex: import CSV en lot) reordonnait "Titres likes"
  // au hasard a chaque appel -- le tri de Dart n'etant pas garanti stable --
  // avec un ordre different d'un appareil a l'autre selon l'ordre d'arrivee
  // des lots de synchro (retour utilisateur : ordre correct sur telephone
  // mais aleatoire sur PC).
  final order = <String, int>{
    for (var i = 0; i < combined.length; i++) combined[i].id: i,
  };
  combined.sort((a, b) {
    final da = a.dateAdded;
    final db = b.dateAdded;
    if (da == null && db == null) return order[a.id]!.compareTo(order[b.id]!);
    if (da == null) return 1;
    if (db == null) return -1;
    final cmp = db.compareTo(da);
    if (cmp != 0) return cmp;
    return order[a.id]!.compareTo(order[b.id]!);
  });
  return combined;
}
