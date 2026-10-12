import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/domain/home_shelves.dart';
import 'package:vinland/domain/liked_tracks.dart';
import 'package:vinland/models/album.dart';
import 'package:vinland/models/track.dart';

Track _t(String id,
        {String artist = 'A',
        int plays = 0,
        DateTime? lastPlayed,
        bool liked = false,
        DateTime? dateAdded}) =>
    Track(
      id: id,
      title: id,
      artist: artist,
      album: 'Album',
      duration: const Duration(minutes: 3),
      playCount: plays,
      lastPlayed: lastPlayed,
      isLiked: liked,
      dateAdded: dateAdded,
    );

void main() {
  final now = DateTime(2026, 10, 12);

  group('HomeShelves', () {
    test('ecoutes de la semaine triees par nombre d\'ecoutes', () {
      final shelves = HomeShelves.compute([
        _t('vieux', plays: 50, lastPlayed: DateTime(2026, 9, 1)),
        _t('peu', plays: 2, lastPlayed: DateTime(2026, 10, 10)),
        _t('beaucoup', plays: 9, lastPlayed: DateTime(2026, 10, 11)),
        _t('jamais'),
      ], const [], now: now);
      expect(shelves.weeklyTracks.map((t) => t.id), ['beaucoup', 'peu']);
    });

    test('artistes du moment par ecoutes cumulees', () {
      final shelves = HomeShelves.compute([
        _t('1', artist: 'X', plays: 3),
        _t('2', artist: 'Y', plays: 4),
        _t('3', artist: 'X', plays: 2),
      ], const [], now: now);
      expect(shelves.topArtists.map((e) => e.$1), ['X', 'Y']);
    });

    test('decouverte : albums ni sauvegardes ni likes, stable sur la journee',
        () {
      final tracks = [_t('l', liked: true), _t('n')];
      final albums = [
        for (var i = 0; i < 15; i++)
          Album(
              id: 'al$i',
              title: 'Album $i',
              artist: 'A',
              trackIds: i == 0 ? ['l'] : ['n']),
      ];
      final first = HomeShelves.compute(tracks, albums, now: now);
      final again = HomeShelves.compute(tracks, albums,
          now: now.add(const Duration(hours: 5)));
      expect(first.discoveryAlbums.length, 10);
      expect(first.discoveryAlbums.any((a) => a.id == 'al0'), isFalse);
      expect(first.discoveryAlbums.map((a) => a.id),
          again.discoveryAlbums.map((a) => a.id));
    });

    test('nouveautes du NAS par date d\'ajout', () {
      final albums = [
        Album(
            id: 'ancien',
            title: 'a',
            artist: 'A',
            trackIds: const [],
            addedToServerAt: DateTime(2026, 1, 1)),
        Album(id: 'sans date', title: 'b', artist: 'A', trackIds: const []),
        Album(
            id: 'recent',
            title: 'c',
            artist: 'A',
            trackIds: const [],
            addedToServerAt: DateTime(2026, 10, 1)),
      ];
      final shelves = HomeShelves.compute(const [], albums, now: now);
      expect(shelves.newOnServerAlbums.map((a) => a.id), ['recent', 'ancien']);
    });
  });

  test(
      'titres likes avec manquants : fantomes intercales par date, ordre '
      'stable entre ex-aequo', () {
    final d1 = DateTime(2026, 10, 1);
    final d2 = DateTime(2026, 10, 2);
    final merged = likedWithMissing([
      _t('recent', dateAdded: d2),
      _t('egal1', dateAdded: d1),
      _t('egal2', dateAdded: d1),
      _t('sans date'),
    ], [
      {
        'title': 'Fantome',
        'artist': 'B',
        'album': 'C',
        'dateAdded': '2026-10-01T12:00:00'
      },
      {'title': 'Sans date', 'artist': 'B', 'album': 'C'},
    ]);
    expect(merged.map((t) => t.id), [
      'recent',
      'missing:Fantome:B:C',
      'egal1',
      'egal2',
      'sans date',
      'missing:Sans date:B:C',
    ]);
  });
}
