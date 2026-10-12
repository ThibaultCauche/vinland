import 'dart:math';

import '../models/album.dart';
import '../models/track.dart';

/// Etageres "suggestions" de l'accueil (Ecoutes cette semaine, Artistes du
/// moment, Decouverte, Nouveautes du NAS), calculees a partir de la
/// bibliotheque. Logique pure : AppState la met en cache plutot que de la
/// recalculer a chaque build de HomeScreen/DesktopHomeView.
class HomeShelves {
  const HomeShelves({
    this.weeklyTracks = const [],
    this.topArtists = const [],
    this.discoveryAlbums = const [],
    this.newOnServerAlbums = const [],
  });

  final List<Track> weeklyTracks;
  final List<(String artist, String? coverPath)> topArtists;
  final List<Album> discoveryAlbums;
  final List<Album> newOnServerAlbums;

  /// `now` fixe la semaine ecoulee et la graine du melange de "Decouverte",
  /// qui reste donc stable sur une journee.
  factory HomeShelves.compute(List<Track> tracks, List<Album> albums,
      {DateTime? now}) {
    final today = now ?? DateTime.now();

    final weekAgo = today.subtract(const Duration(days: 7));
    final recent = tracks
        .where((t) =>
            t.playCount > 0 &&
            t.lastPlayed != null &&
            t.lastPlayed!.isAfter(weekAgo))
        .toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));

    final playsByArtist = <String, int>{};
    final coverByArtist = <String, String?>{};
    for (final t in tracks) {
      if (t.playCount <= 0) continue;
      playsByArtist.update(t.artist, (v) => v + t.playCount,
          ifAbsent: () => t.playCount);
      coverByArtist.putIfAbsent(t.artist, () => t.coverPath);
    }
    final artistNames = playsByArtist.keys.toList()
      ..sort((a, b) => playsByArtist[b]!.compareTo(playsByArtist[a]!));

    final tracksById = {for (final t in tracks) t.id: t};
    final notLiked = albums.where((a) {
      if (a.isSaved) return false;
      return a.trackIds.every((id) => tracksById[id]?.isLiked != true);
    }).toList();
    final seed = today.year * 10000 + today.month * 100 + today.day;

    final withDate = albums.where((a) => a.addedToServerAt != null).toList()
      ..sort((a, b) => b.addedToServerAt!.compareTo(a.addedToServerAt!));

    return HomeShelves(
      weeklyTracks: recent.take(10).toList(),
      topArtists:
          artistNames.take(10).map((a) => (a, coverByArtist[a])).toList(),
      discoveryAlbums:
          (List<Album>.of(notLiked)..shuffle(Random(seed))).take(10).toList(),
      newOnServerAlbums: withDate.take(10).toList(),
    );
  }
}
