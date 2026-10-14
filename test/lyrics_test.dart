import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinland/domain/lyrics.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/lyrics_service.dart';
import 'package:vinland/services/subsonic_refs.dart';

Track _track({bool nas = true}) => Track(
      id: nas ? 'navidrome_42' : 'local_1',
      title: 'Hey Jude',
      artist: 'The Beatles',
      album: 'Past Masters',
      duration: const Duration(minutes: 7, seconds: 11),
      filePath: nas ? SubsonicRefs.stream('42') : '/music/hey_jude.mp3',
    );

void main() {
  group('Lyrics.parseLrc', () {
    test('lit les instants, trie et ignore les en-tetes', () {
      final lyrics = Lyrics.parseLrc('''
[ar:The Beatles]
[ti:Hey Jude]
[00:12.50]Take a sad song
[00:05.1]Hey Jude
[01:02.003]Na na na
''', source: 'test');
      expect(lyrics.isSynced, isTrue);
      expect(lyrics.lines, [
        const LyricLine('Hey Jude',
            start: Duration(seconds: 5, milliseconds: 100)),
        const LyricLine('Take a sad song',
            start: Duration(seconds: 12, milliseconds: 500)),
        const LyricLine('Na na na',
            start: Duration(minutes: 1, seconds: 2, milliseconds: 3)),
      ]);
    });

    test('une ligne a plusieurs instants (refrain) est dupliquee', () {
      final lyrics = Lyrics.parseLrc(
          '[00:10.00][00:30.00]Refrain\n[00:20.00]Couplet',
          source: 'test');
      expect(
          lyrics.lines.map((l) => l.text), ['Refrain', 'Couplet', 'Refrain']);
    });

    test('offset positif avance les paroles, sans passer sous zero', () {
      final lyrics = Lyrics.parseLrc('[offset:+500]\n[00:00.20]A\n[00:02.00]B',
          source: 'test');
      expect(lyrics.lines.map((l) => l.start), [
        Duration.zero,
        const Duration(milliseconds: 1500),
      ]);
    });

    test('sans aucun instant : paroles simples', () {
      final lyrics = Lyrics.parseLrc('\nLigne 1\n\nLigne 2\n', source: 'test');
      expect(lyrics.isSynced, isFalse);
      expect(lyrics.lines.map((l) => l.text), ['Ligne 1', '', 'Ligne 2']);
    });
  });

  group('Lyrics.activeIndex', () {
    final lyrics = Lyrics([
      for (final s in [5, 10, 15])
        LyricLine('l$s', start: Duration(seconds: s)),
    ], source: 'test');

    test('derniere ligne commencee', () {
      expect(lyrics.activeIndex(const Duration(seconds: 2)), -1);
      expect(lyrics.activeIndex(const Duration(seconds: 5)), 0);
      expect(lyrics.activeIndex(const Duration(seconds: 12)), 1);
      expect(lyrics.activeIndex(const Duration(minutes: 3)), 2);
    });

    test('-1 pour des paroles simples', () {
      expect(Lyrics.plain('a\nb', source: 't').activeIndex(Duration.zero), -1);
    });
  });

  group('LyricsService', () {
    Map<String, dynamic> nasEntry({required bool synced}) => {
          'synced': synced,
          'offset': 100,
          'line': [
            {if (synced) 'start': 1000, 'value': 'Hey Jude'},
            {if (synced) 'start': 3000, 'value': "don't make it bad"},
          ],
        };

    http.Client lrclib(
        {int status = 200, Map<String, dynamic>? body, List<Uri>? calls}) {
      return MockClient((request) async {
        calls?.add(request.url);
        return http.Response(jsonEncode(body ?? {}), status);
      });
    }

    test('paroles synchronisees du NAS : LRCLIB n est pas appele', () async {
      final calls = <Uri>[];
      final service = LyricsService(
        navidromeLyrics: (_) async => [nasEntry(synced: true)],
        client: lrclib(calls: calls),
      );
      final lyrics = await service.lyricsFor(_track());
      expect(lyrics!.source, 'Navidrome');
      expect(lyrics.isSynced, isTrue);
      expect(lyrics.lines.first.start, const Duration(milliseconds: 900));
      expect(calls, isEmpty);
    });

    test('paroles simples du NAS : LRCLIB synchronise passe devant', () async {
      final service = LyricsService(
        navidromeLyrics: (_) async => [nasEntry(synced: false)],
        client: lrclib(body: {
          'syncedLyrics': '[00:01.00]Hey Jude\n[00:03.00]Refrain',
          'plainLyrics': 'Hey Jude\nRefrain',
        }),
      );
      final lyrics = await service.lyricsFor(_track());
      expect(lyrics!.source, 'LRCLIB');
      expect(lyrics.isSynced, isTrue);
    });

    test('paroles simples du NAS gardees si LRCLIB n a que du texte', () async {
      final service = LyricsService(
        navidromeLyrics: (_) async => [nasEntry(synced: false)],
        client: lrclib(body: {'plainLyrics': 'autre texte'}),
      );
      final lyrics = await service.lyricsFor(_track());
      expect(lyrics!.source, 'Navidrome');
    });

    test('titre local : seul LRCLIB est interroge, avec la duree', () async {
      final calls = <Uri>[];
      var nasCalled = false;
      final service = LyricsService(
        navidromeLyrics: (_) async {
          nasCalled = true;
          return const [];
        },
        client: lrclib(body: {'plainLyrics': 'texte'}, calls: calls),
      );
      await service.lyricsFor(_track(nas: false));
      expect(nasCalled, isFalse);
      expect(calls.single.host, 'lrclib.net');
      expect(calls.single.queryParameters['duration'], '431');
      expect(calls.single.queryParameters['artist_name'], 'The Beatles');
    });

    test('rien trouve : null, garde en cache', () async {
      final calls = <Uri>[];
      final service = LyricsService(
        navidromeLyrics: (_) async => const [],
        client: lrclib(status: 404, calls: calls),
      );
      expect(await service.lyricsFor(_track()), isNull);
      expect(await service.lyricsFor(_track()), isNull);
      expect(calls, hasLength(1));
    });

    test('erreur reseau : pas retenue, on reessaie la fois suivante', () async {
      final calls = <Uri>[];
      final service = LyricsService(
        navidromeLyrics: (_) async => const [],
        client: lrclib(status: 500, calls: calls),
      );
      expect(await service.lyricsFor(_track()), isNull);
      expect(await service.lyricsFor(_track()), isNull);
      expect(calls, hasLength(2));
    });

    test('titre instrumental sur LRCLIB : pas de paroles', () {
      expect(
          LyricsService.fromLrclibJson(
              {'instrumental': true, 'plainLyrics': ''}),
          isNull);
    });
  });
}
