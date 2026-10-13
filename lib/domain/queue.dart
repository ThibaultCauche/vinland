import 'dart:math';

import '../models/track.dart';

/// File d'attente de lecture : titres a venir, ordre d'origine du contexte
/// lance (album, playlist, titres likes, artiste) et historique pour le
/// bouton "precedent". Logique pure, sans Flutter ni moteur audio, pour
/// pouvoir la tester exhaustivement (voir test/domain/queue_test.dart) --
/// c'est PlayerController qui decide quand l'appeler et quoi jouer ensuite.
///
/// Un seul titre a la fois est confie au moteur audio : next/previous/
/// shuffle sont geres ici, jamais delegues au shuffle natif de just_audio/
/// mpv (source du bug ou le titre affiche desynchronisait du titre
/// reellement joue, et ou le tout premier titre de "Titres likes" revenait
/// bien plus souvent que les autres a chaque fin de cycle melange).
class PlayQueue {
  PlayQueue({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// Bornee pour ne pas grossir indefiniment sur une tres longue session
  /// d'ecoute.
  static const int maxHistory = 200;

  /// "Titres a venir", dans l'ordre d'ecoute -- visible/reordonnable par
  /// l'utilisateur (voir QueueScreen), completee par "Ajouter a la file
  /// d'attente". Ne contient JAMAIS le titre en cours.
  ///
  /// Liste exposee telle quelle et modifiee sur place pour les petites
  /// operations (ajout, retrait, reordonnancement), remplacee pour les
  /// grosses (nouveau contexte, remelange) : c'etait deja le cas quand elle
  /// vivait dans AppState, et les Selector de QueueScreen/DesktopQueuePanel
  /// comparent cette liste par identite -- garder exactement ce comportement
  /// tant que ces ecrans ne sont pas migres.
  List<Track> upcoming = [];

  // Ordre d'origine de la collection lancee : sert a regenerer `upcoming`
  // quand on (re)active le mode aleatoire ou quand la file est epuisee (on
  // reboucle sur ce meme contexte plutot que de s'arreter net, cf. retour
  // des beta-testeurs).
  List<Track> _sourceOrder = [];
  final List<Track> _history = [];

  List<Track> get sourceOrder => List.unmodifiable(_sourceOrder);
  List<Track> get history => List.unmodifiable(_history);
  bool get hasHistory => _history.isNotEmpty;

  void _pushHistory(Track track) {
    _history.add(track);
    if (_history.length > maxHistory) _history.removeAt(0);
  }

  /// Nouveau contexte : tout ce qui suit `track` dans `trackList` devient la
  /// file (melangee une fois si `shuffled`), et `trackList` devient l'ordre
  /// d'origine. L'historique repart de zero.
  void start(Track track, List<Track>? trackList, {required bool shuffled}) {
    _history.clear();
    _sourceOrder = trackList ?? [track];
    final startIndex = _sourceOrder.indexWhere((t) => t.id == track.id);
    // En aleatoire, toute la liste sauf le titre tape (comme reshuffle) : se
    // limiter a ce qui le suit laissait la file vide en tapant le dernier
    // titre d'une liste, et ne melangeait jamais ceux d'avant.
    if (shuffled) {
      upcoming = _sourceOrder.where((t) => t.id != track.id).toList()
        ..shuffle(_random);
      return;
    }
    upcoming =
        startIndex == -1 ? <Track>[] : _sourceOrder.sublist(startIndex + 1);
  }

  /// Titre suivant (retire de la file), `current` passant dans
  /// l'historique. File vide : la regenere depuis l'ordre d'origine au lieu
  /// de s'arreter net -- c'est le "reboucler sur la meme file" attendu par
  /// les beta-testeurs, que la lecture aleatoire soit active ou non (avant,
  /// ce rebouclage rejouait toujours le tout premier titre de la liste
  /// d'origine meme en mode aleatoire). Null s'il n'y a rien a jouer.
  Track? advance(Track? current, {required bool shuffled}) {
    if (upcoming.isEmpty) {
      if (_sourceOrder.isEmpty) return null;
      final playedIds = {if (current != null) current.id};
      var refill =
          _sourceOrder.where((t) => !playedIds.contains(t.id)).toList();
      if (refill.isEmpty) refill = List<Track>.of(_sourceOrder);
      if (shuffled) refill.shuffle(_random);
      upcoming = refill;
    }
    if (upcoming.isEmpty) return null;
    if (current != null) _pushHistory(current);
    return upcoming.removeAt(0);
  }

  /// Saute directement au titre en position `index` : tout ce qui le
  /// precedait est abandonne (jamais joue, donc pas ajoute a l'historique).
  Track? skipTo(int index, Track? current) {
    if (index < 0 || index >= upcoming.length) return null;
    if (current != null) _pushHistory(current);
    upcoming.removeRange(0, index);
    return upcoming.removeAt(0);
  }

  /// Revient au dernier titre de l'historique, `current` repassant en tete
  /// de file. Null si l'historique est vide.
  Track? back(Track? current) {
    if (_history.isEmpty) return null;
    if (current != null) upcoming.insert(0, current);
    return _history.removeLast();
  }

  /// "Ajouter a la file d'attente" : a la fin.
  void add(Track track) => upcoming.add(track);

  /// "Lire ensuite" : en tete, donc juste apres le titre en cours. Pour
  /// plusieurs titres d'un coup (ex: un album entier), appeler dans l'ordre
  /// inverse voulu.
  void insertNext(Track track) => upcoming.insert(0, track);

  void removeAt(int index) {
    if (index < 0 || index >= upcoming.length) return;
    upcoming.removeAt(index);
  }

  /// [newIndex] est la position finale du titre (convention de
  /// ReorderableListView.onReorderItem, utilisee par QueueScreen et
  /// DesktopQueuePanel depuis le passage a Flutter 3.47) : pas de
  /// "newIndex -= 1" a faire ici, sinon un titre glisse vers le bas
  /// atterrit une place trop haut.
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= upcoming.length) return;
    final item = upcoming.removeAt(oldIndex);
    upcoming.insert(newIndex.clamp(0, upcoming.length), item);
  }

  /// Regenere la partie "contexte" de la file (ce qui reste de l'ordre
  /// d'origine a jouer) -- melangee si `shuffled`, ordre d'origine sinon --
  /// en preservant en tete, inchanges, les titres ajoutes a la main qui ne
  /// font pas partie de ce contexte.
  void reshuffle({required bool shuffled, Track? current}) {
    final playedIds = {
      ..._history.map((t) => t.id),
      if (current != null) current.id,
    };
    final contextRemainder =
        _sourceOrder.where((t) => !playedIds.contains(t.id)).toList();
    if (shuffled) contextRemainder.shuffle(_random);
    final manuallyQueued =
        upcoming.where((t) => !_sourceOrder.any((s) => s.id == t.id)).toList();
    upcoming = [...manuallyQueued, ...contextRemainder];
  }

  /// Remplace la file telle quelle (file de l'hote recue en Jam), sans
  /// toucher a l'ordre d'origine ni a l'historique.
  void replaceUpcoming(List<Track> tracks) => upcoming = tracks;

  /// Restaure une file sauvegardee (redemarrage de l'app).
  void restore({required List<Track> upcoming, required List<Track> source}) {
    this.upcoming = upcoming;
    _sourceOrder = source;
  }

  void clear() {
    upcoming = [];
    _sourceOrder = [];
    _history.clear();
  }
}

/// Vrai si [next] suit directement [previous] sur le meme album (piste
/// suivante, ou premiere piste du disque suivant). Ces titres ne sont jamais
/// fondus l'un dans l'autre : sur un live, un mix ou un album concept, la
/// fin d'un titre EST le debut du suivant, et un fondu y creuserait un trou
/// de volume en plein morceau. Subsonic n'expose pas le tag « gapless »,
/// l'ordre de l'album est le seul indice fiable.
bool continuesOnDisc(Track previous, Track next) {
  if (previous.albumId == null || previous.albumId != next.albumId) {
    return false;
  }
  final a = previous.trackNumber;
  final b = next.trackNumber;
  if (a == null || b == null) return false;
  final discA = previous.discNumber ?? 1;
  final discB = next.discNumber ?? 1;
  return (discA == discB && b == a + 1) || (discB == discA + 1 && b == 1);
}
