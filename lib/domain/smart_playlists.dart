import '../models/playlist.dart';
import '../models/track.dart';

/// Playlists intelligentes : listes qui se remplissent toutes seules a
/// partir de la bibliotheque (ecoutes, likes, dates d'ajout, annees), et se
/// mettent a jour a chaque ouverture. Logique pure, testee sans app.
///
/// Elles ne sont pas creees sur Navidrome : « Enregistrer dans ma
/// bibliotheque » en fait une vraie playlist, figee a ce moment-la.
class SmartPlaylist {
  const SmartPlaylist({
    required this.id,
    required this.name,
    required this.description,
    required this.tracks,
  });

  /// Prefixe des ids : jamais confondu avec une vraie playlist.
  static const idPrefix = 'smart:';

  final String id;
  final String name;
  final String description;
  final List<Track> tracks;

  /// Playlist en lecture seule, pour les ecrans qui affichent une Playlist.
  Playlist toPlaylist() => Playlist(
        id: id,
        name: name,
        trackIds: [for (final t in tracks) t.id],
      );

  /// En dessous, la playlist n'est pas proposee (une liste de 2 titres
  /// n'aide personne).
  static const minTracks = 5;

  /// Taille maximale d'une liste : assez pour une soiree, sans noyer.
  static const maxTracks = 200;

  /// Toutes les playlists qui ont assez de titres, dans l'ordre d'affichage.
  /// [now] fixe « recemment » et « il y a longtemps » (tests).
  static List<SmartPlaylist> compute(List<Track> library, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final tracks = library.where((t) => !t.isPlaceholder).toList();

    DateTime? added(Track t) => t.addedToServerAt ?? t.dateAdded;
    bool playedSince(Track t, Duration d) =>
        t.lastPlayed != null && t.lastPlayed!.isAfter(today.subtract(d));

    final candidates = <SmartPlaylist>[
      SmartPlaylist(
        id: '${idPrefix}recent',
        name: 'Ajoutés ce mois-ci',
        description: 'Arrivés sur le NAS ces 30 derniers jours',
        tracks: _sorted(
          tracks.where((t) =>
              added(t) != null &&
              added(t)!.isAfter(today.subtract(const Duration(days: 30)))),
          (a, b) => added(b)!.compareTo(added(a)!),
        ),
      ),
      SmartPlaylist(
        id: '${idPrefix}never',
        name: 'Jamais écoutés',
        description: 'Dans ta bibliothèque, jamais lancés',
        tracks: _sorted(
          tracks.where((t) => t.playCount == 0 && t.lastPlayed == null),
          // Les plus recents d'abord : ce qu'on vient d'ajouter sans
          // l'avoir encore ecoute.
          (a, b) =>
              (added(b) ?? DateTime(0)).compareTo(added(a) ?? DateTime(0)),
        ),
      ),
      SmartPlaylist(
        id: '${idPrefix}top',
        name: 'Tes classiques',
        description: 'Tes titres les plus écoutés',
        tracks: _sorted(
          tracks.where((t) => t.playCount >= 3),
          (a, b) => b.playCount.compareTo(a.playCount),
        ),
      ),
      SmartPlaylist(
        id: '${idPrefix}forgotten-likes',
        name: 'Likés oubliés',
        description: 'Des titres likés pas écoutés depuis 3 mois',
        tracks: _sorted(
          tracks.where(
              (t) => t.isLiked && !playedSince(t, const Duration(days: 90))),
          (a, b) => (a.lastPlayed ?? DateTime(0))
              .compareTo(b.lastPlayed ?? DateTime(0)),
        ),
      ),
      SmartPlaylist(
        id: '${idPrefix}rediscover',
        name: 'À redécouvrir',
        description: 'Souvent écoutés, mais plus depuis 6 mois',
        tracks: _sorted(
          tracks.where((t) =>
              t.playCount >= 5 &&
              t.lastPlayed != null &&
              !playedSince(t, const Duration(days: 180))),
          (a, b) => b.playCount.compareTo(a.playCount),
        ),
      ),
      ..._decades(tracks),
    ];
    return [
      for (final p in candidates)
        if (p.tracks.length >= minTracks) p
    ];
  }

  /// Une playlist par decennie (« Années 90 »), de la plus ancienne a la
  /// plus recente, a partir de l'annee des tags.
  static List<SmartPlaylist> _decades(List<Track> tracks) {
    final byDecade = <int, List<Track>>{};
    for (final t in tracks) {
      final year = t.year;
      if (year == null || year < 1900) continue;
      byDecade.putIfAbsent(year ~/ 10 * 10, () => []).add(t);
    }
    final decades = byDecade.keys.toList()..sort();
    return [
      for (final d in decades)
        SmartPlaylist(
          id: '${idPrefix}decade-$d',
          name: decadeLabel(d),
          description: 'Sortis entre $d et ${d + 9}',
          // Les plus ecoutes d'abord : une decennie de 800 titres reste
          // representative une fois coupee a maxTracks.
          tracks: _sorted(byDecade[d]!, (a, b) {
            final byPlays = b.playCount.compareTo(a.playCount);
            return byPlays != 0 ? byPlays : a.year!.compareTo(b.year!);
          }),
        ),
    ];
  }

  /// « Années 80 », « Années 2000 », « Années 2010 ».
  static String decadeLabel(int decade) => decade >= 2000 || decade < 1900
      ? 'Années $decade'
      : 'Années ${decade % 100}';

  static List<Track> _sorted(
      Iterable<Track> tracks, int Function(Track, Track) compare) {
    final list = tracks.toList()..sort(compare);
    return list.length > maxTracks ? list.sublist(0, maxTracks) : list;
  }
}
