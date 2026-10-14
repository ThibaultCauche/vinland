import '../models/track.dart';

/// Une ecoute du journal (voir ListeningLog) : quand, et une copie de ce
/// qu'etait le titre a ce moment. La copie compte : le NAS supprime de
/// lui-meme les titres peu ecoutes, et le bilan de l'annee doit pouvoir
/// citer un titre qui n'est plus dans la bibliotheque.
class PlayEvent {
  const PlayEvent({
    required this.at,
    required this.trackId,
    required this.title,
    required this.artist,
    this.album = '',
    this.genre,
    this.duration = Duration.zero,
  });

  factory PlayEvent.fromTrack(Track t, DateTime at) => PlayEvent(
        at: at,
        trackId: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        genre: t.genre,
        duration: t.duration,
      );

  final DateTime at;
  final String trackId;
  final String title;
  final String artist;
  final String album;
  final String? genre;
  final Duration duration;

  /// Cles courtes : une ligne par ecoute, des milliers par an.
  Map<String, dynamic> toJson() => {
        't': at.millisecondsSinceEpoch,
        'id': trackId,
        'ti': title,
        'ar': artist,
        if (album.isNotEmpty) 'al': album,
        if (genre != null && genre!.isNotEmpty) 'g': genre,
        if (duration > Duration.zero) 'd': duration.inSeconds,
      };

  /// Null pour une ligne abimee (coupure pendant l'ecriture) : on la saute.
  static PlayEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final t = json['t'], id = json['id'], ti = json['ti'], ar = json['ar'];
    if (t is! int || id is! String || ti is! String || ar is! String) {
      return null;
    }
    return PlayEvent(
      at: DateTime.fromMillisecondsSinceEpoch(t),
      trackId: id,
      title: ti,
      artist: ar,
      album: json['al'] is String ? json['al'] as String : '',
      genre: json['g'] is String ? json['g'] as String : null,
      duration: Duration(seconds: json['d'] is int ? json['d'] as int : 0),
    );
  }
}

/// Un element classe : nom, sous-titre (artiste d'un titre...), ecoutes.
class Ranked {
  const Ranked(this.name, this.plays, {this.subtitle, this.trackId});
  final String name;
  final String? subtitle;
  final int plays;

  /// Id du titre (classement des titres), pour retrouver sa pochette.
  final String? trackId;

  @override
  String toString() => 'Ranked($name, $plays)';
}

/// Bilan d'ecoute (« Wrapped ») d'une annee, ou de tout l'historique.
class ListeningStats {
  const ListeningStats({
    required this.label,
    required this.plays,
    required this.listened,
    required this.distinctArtists,
    required this.distinctTracks,
    required this.topArtists,
    required this.topTracks,
    required this.topAlbums,
    required this.topGenres,
    this.busiestMonth,
    this.busiestDay,
    this.firstPlay,
    this.isEstimate = false,
  });

  /// « 2026 » ou « Depuis toujours ».
  final String label;
  final int plays;

  /// Duree cumulee des titres lances (approximation : un titre passe avant
  /// la fin compte en entier).
  final Duration listened;
  final int distinctArtists;
  final int distinctTracks;
  final List<Ranked> topArtists;
  final List<Ranked> topTracks;
  final List<Ranked> topAlbums;
  final List<Ranked> topGenres;

  /// Mois (1-12) le plus ecoute de l'annee, et le nombre d'ecoutes.
  final (int month, int plays)? busiestMonth;

  /// Jour le plus ecoute, et le nombre d'ecoutes.
  final (DateTime day, int plays)? busiestDay;

  /// Premiere ecoute de la periode.
  final PlayEvent? firstPlay;

  /// Vrai pour le bilan « Depuis toujours » tire des compteurs de la
  /// bibliotheque (pas de dates, titres encore presents seulement).
  final bool isEstimate;

  bool get isEmpty => plays == 0;

  static const topSize = 5;

  /// Annees presentes dans le journal, de la plus recente a la plus
  /// ancienne.
  static List<int> yearsOf(Iterable<PlayEvent> events) =>
      ({for (final e in events) e.at.year}.toList()..sort()).reversed.toList();

  /// Bilan de l'annee [year] a partir du journal d'ecoute.
  static ListeningStats forYear(Iterable<PlayEvent> events, int year) {
    final inYear = events.where((e) => e.at.year == year).toList()
      ..sort((a, b) => a.at.compareTo(b.at));

    final artists = <String, int>{};
    final tracks = <String, (PlayEvent, int)>{};
    final albums = <String, (String, String, int)>{};
    final genres = <String, int>{};
    final months = <int, int>{};
    final days = <DateTime, int>{};
    var listened = Duration.zero;

    for (final e in inYear) {
      listened += e.duration;
      artists.update(e.artist, (n) => n + 1, ifAbsent: () => 1);
      final trackKey = '${e.artist.toLowerCase()}|${e.title.toLowerCase()}';
      tracks.update(trackKey, (v) => (v.$1, v.$2 + 1), ifAbsent: () => (e, 1));
      if (e.album.isNotEmpty) {
        albums.update('${e.artist}|${e.album}', (v) => (v.$1, v.$2, v.$3 + 1),
            ifAbsent: () => (e.album, e.artist, 1));
      }
      final genre = e.genre?.trim();
      if (genre != null && genre.isNotEmpty) {
        genres.update(genre, (n) => n + 1, ifAbsent: () => 1);
      }
      months.update(e.at.month, (n) => n + 1, ifAbsent: () => 1);
      final day = DateTime(e.at.year, e.at.month, e.at.day);
      days.update(day, (n) => n + 1, ifAbsent: () => 1);
    }

    return ListeningStats(
      label: '$year',
      plays: inYear.length,
      listened: listened,
      distinctArtists: artists.length,
      distinctTracks: tracks.length,
      topArtists: _top(artists.entries.map((e) => Ranked(e.key, e.value))),
      topTracks: _top(tracks.values.map((v) => Ranked(v.$1.title, v.$2,
          subtitle: v.$1.artist, trackId: v.$1.trackId))),
      topAlbums:
          _top(albums.values.map((v) => Ranked(v.$1, v.$3, subtitle: v.$2))),
      topGenres: _top(genres.entries.map((e) => Ranked(e.key, e.value))),
      busiestMonth: _max(months),
      busiestDay: _max(days),
      firstPlay: inYear.isEmpty ? null : inYear.first,
    );
  }

  /// Bilan « Depuis toujours » a partir des compteurs d'ecoute de la
  /// bibliotheque : sert tant que le journal est vide (il ne commence qu'a
  /// cette version) et pour une vue d'ensemble.
  static ListeningStats allTime(List<Track> library) {
    final played = library.where((t) => t.playCount > 0).toList();
    final artists = <String, int>{};
    final albums = <String, (String, String, int)>{};
    final genres = <String, int>{};
    var plays = 0;
    var listened = Duration.zero;
    for (final t in played) {
      plays += t.playCount;
      listened += t.duration * t.playCount;
      artists.update(t.artist, (n) => n + t.playCount,
          ifAbsent: () => t.playCount);
      if (t.album.isNotEmpty) {
        albums.update(
            '${t.artist}|${t.album}', (v) => (v.$1, v.$2, v.$3 + t.playCount),
            ifAbsent: () => (t.album, t.artist, t.playCount));
      }
      final genre = t.genre?.trim();
      if (genre != null && genre.isNotEmpty) {
        genres.update(genre, (n) => n + t.playCount,
            ifAbsent: () => t.playCount);
      }
    }
    return ListeningStats(
      label: 'Depuis toujours',
      plays: plays,
      listened: listened,
      distinctArtists: artists.length,
      distinctTracks: played.length,
      topArtists: _top(artists.entries.map((e) => Ranked(e.key, e.value))),
      topTracks: _top(played.map((t) =>
          Ranked(t.title, t.playCount, subtitle: t.artist, trackId: t.id))),
      topAlbums:
          _top(albums.values.map((v) => Ranked(v.$1, v.$3, subtitle: v.$2))),
      topGenres: _top(genres.entries.map((e) => Ranked(e.key, e.value))),
      isEstimate: true,
    );
  }

  /// Les [topSize] premiers, ex aequo departages par ordre alphabetique
  /// (resultat stable d'un affichage a l'autre).
  static List<Ranked> _top(Iterable<Ranked> items) {
    final list = items.toList()
      ..sort((a, b) {
        final byPlays = b.plays.compareTo(a.plays);
        return byPlays != 0
            ? byPlays
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list.take(topSize).toList();
  }

  static (K, int)? _max<K extends Comparable<dynamic>>(Map<K, int> counts) {
    (K, int)? best;
    for (final e in counts.entries) {
      if (best == null ||
          e.value > best.$2 ||
          (e.value == best.$2 && e.key.compareTo(best.$1) < 0)) {
        best = (e.key, e.value);
      }
    }
    return best;
  }
}
