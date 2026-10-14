import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vinland/domain/listening_stats.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/listening_log.dart';
import 'package:vinland/services/party/party_models.dart';

PlayEvent _e(String title, String artist, DateTime at,
        {String album = 'Album', String? genre, int seconds = 180}) =>
    PlayEvent(
      at: at,
      trackId: 'navidrome_$title',
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      duration: Duration(seconds: seconds),
    );

void main() {
  group('ListeningStats.forYear', () {
    final events = [
      _e('A', 'Muse', DateTime(2026, 3, 1, 10), genre: 'Rock'),
      _e('A', 'Muse', DateTime(2026, 3, 1, 11), genre: 'Rock'),
      _e('B', 'Muse', DateTime(2026, 3, 2), genre: 'Rock'),
      _e('C', 'Daft Punk', DateTime(2026, 7, 14), genre: 'Électro'),
      _e('C', 'Daft Punk', DateTime(2026, 1, 5, 8), genre: 'Électro'),
      _e('Z', 'Ancien', DateTime(2025, 12, 31)),
    ];
    final stats = ListeningStats.forYear(events, 2026);

    test('ne compte que l annee demandee', () {
      expect(stats.plays, 5);
      expect(stats.listened, const Duration(minutes: 15));
      expect(stats.distinctArtists, 2);
      expect(stats.distinctTracks, 3);
    });

    test('classements du plus au moins ecoute', () {
      expect(stats.topArtists.map((r) => (r.name, r.plays)),
          [('Muse', 3), ('Daft Punk', 2)]);
      expect(stats.topTracks.first.name, 'A');
      expect(stats.topTracks.first.subtitle, 'Muse');
      // Ex aequo (A n'a que 2 comme C) : ordre alphabetique.
      expect(stats.topTracks.map((r) => r.name), ['A', 'C', 'B']);
      expect(stats.topGenres.first.name, 'Rock');
    });

    test('moments forts : mois, jour record, premiere ecoute', () {
      expect(stats.busiestMonth, (3, 3));
      expect(stats.busiestDay, (DateTime(2026, 3, 1), 2));
      expect(stats.firstPlay!.title, 'C');
    });

    test('annees presentes, la plus recente d abord', () {
      expect(ListeningStats.yearsOf(events), [2026, 2025]);
    });

    test('annee sans ecoute : bilan vide', () {
      expect(ListeningStats.forYear(events, 2020).isEmpty, isTrue);
    });

    test('pas plus de 5 par classement', () {
      final many = [
        for (var i = 0; i < 8; i++) _e('T$i', 'Artiste $i', DateTime(2026))
      ];
      expect(ListeningStats.forYear(many, 2026).topArtists, hasLength(5));
    });
  });

  test('depuis toujours : a partir des compteurs de la bibliotheque', () {
    Track t(String id, String artist, int plays) => Track(
          id: id,
          title: id,
          artist: artist,
          album: 'Album',
          duration: const Duration(minutes: 4),
          playCount: plays,
        );
    final stats = ListeningStats.allTime([
      t('a', 'Muse', 10),
      t('b', 'Muse', 2),
      t('c', 'Air', 5),
      t('d', 'X', 0)
    ]);
    expect(stats.isEstimate, isTrue);
    expect(stats.plays, 17);
    expect(stats.listened, const Duration(minutes: 68));
    expect(stats.topArtists.first.name, 'Muse');
    expect(stats.topTracks.map((r) => r.name), ['a', 'c', 'b']);
    expect(stats.distinctTracks, 3);
  });

  group('ListeningLog', () {
    test('ajoute puis relit les ecoutes', () async {
      final dir = await Directory.systemTemp.createTemp('vinland_log');
      addTearDown(() => dir.delete(recursive: true));
      final log = ListeningLog(p.join(dir.path, 'userdata', 'plays.jsonl'));
      expect(await log.readAll(), isEmpty);
      await log.append(_e('A', 'Muse', DateTime(2026, 5, 1), genre: 'Rock'));
      await log.append(_e('B', 'Air', DateTime(2026, 5, 2), album: ''));
      final events = await log.readAll();
      expect(events.map((e) => e.title), ['A', 'B']);
      expect(events.first.genre, 'Rock');
      expect(events.first.duration, const Duration(minutes: 3));
      expect(events.last.album, '');
      expect(events.first.at, DateTime(2026, 5, 1));
    });

    test('une ligne coupee par un arret brutal est ignoree', () {
      final events = ListeningLog.parse(
          '{"t":1,"id":"a","ti":"A","ar":"Muse"}\n{"t":2,"id":"b","ti');
      expect(events.map((e) => e.title), ['A']);
    });
  });

  group('partyRecapHighlights', () {
    PartyPlayed played(String by, String artist, DateTime at) => PartyPlayed(
        song: PartySong(songId: 's', title: 't', artist: artist),
        by: by,
        at: at);

    test('duree, DJ de la soiree et artiste le plus joue', () {
      final start = DateTime(2026, 10, 10, 21);
      final lines = partyRecapHighlights([
        played('Léa', 'Muse', start),
        played('Léa', 'Muse', start.add(const Duration(minutes: 40))),
        played('Tom', 'Air', start.add(const Duration(hours: 1))),
        played('Radio', 'Air', start.add(const Duration(hours: 2))),
        played('Léa', 'Muse', start.add(const Duration(hours: 3, minutes: 5))),
      ]);
      expect(lines, [
        'Durée : 3 h 05',
        'DJ de la soirée : Léa (3 titres)',
        'Artiste le plus joué : Muse (3 fois)',
      ]);
    });

    test('ex aequo ou soiree courte : rien d inventé', () {
      final at = DateTime(2026, 10, 10, 21);
      expect(
          partyRecapHighlights([
            played('Léa', 'Muse', at),
            played('Tom', 'Air', at),
          ]),
          isEmpty);
      expect(partyRecapHighlights([]), isEmpty);
    });
  });
}
