import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/models/album.dart';
import 'package:vinland/models/recent_play.dart';
import 'package:vinland/models/search_history_item.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/subsonic_refs.dart';

/// Un cache JSON ne doit jamais contenir le jeton ni le sel Subsonic.
void _expectNoToken(Object json) {
  final encoded = jsonEncode(json);
  expect(encoded, isNot(contains('t=')));
  expect(encoded, isNot(contains('s=')));
  expect(encoded, isNot(contains('/rest/')));
}

void main() {
  setUp(() {
    // Simule NavidromeService : URL construites avec le jeton de la session.
    SubsonicRefs.streamUrlBuilder =
        (id) => 'https://nas.example/rest/stream.view?id=$id&t=jeton&s=sel';
    SubsonicRefs.coverUrlBuilder = (id) =>
        'https://nas.example/rest/getCoverArt.view?id=$id&t=jeton&s=sel';
  });

  tearDown(() {
    SubsonicRefs.streamUrlBuilder = null;
    SubsonicRefs.coverUrlBuilder = null;
  });

  group('Track', () {
    test('le cache de bibliotheque ne contient plus le jeton Subsonic', () {
      final track = Track(
        id: 'navidrome_42',
        title: 'Titre',
        artist: 'Artiste',
        album: 'Album',
        duration: const Duration(minutes: 3),
        filePath: SubsonicRefs.stream('42'),
        coverPath: SubsonicRefs.cover('mf-42'),
      );

      final json = track.toJson();

      _expectNoToken(json);
      expect(json['subsonicId'], '42');
      expect(json['coverArtId'], 'mf-42');
      expect(json.containsKey('filePath'), isFalse);
      expect(json.containsKey('coverPath'), isFalse);
    });

    test('l URL de lecture est reconstruite a la demande avec le jeton courant',
        () {
      final track = Track.fromJson({
        'id': 'navidrome_42',
        'title': 'Titre',
        'artist': 'Artiste',
        'album': 'Album',
        'duration': 1000,
        'subsonicId': '42',
        'coverArtId': 'mf-42',
      });

      expect(track.filePath,
          'https://nas.example/rest/stream.view?id=42&t=jeton&s=sel');
      expect(track.coverPath,
          'https://nas.example/rest/getCoverArt.view?id=mf-42&t=jeton&s=sel');
      expect(track.isPlaceholder, isFalse);

      // Nouveau sel au demarrage suivant : rien a migrer, l'URL suit.
      SubsonicRefs.streamUrlBuilder =
          (id) => 'https://nas.example/rest/stream.view?id=$id&t=autre&s=sel2';
      expect(track.filePath, contains('t=autre'));
    });

    test('un fichier local garde son chemin tel quel', () {
      final track = Track(
        id: '/musique/a.mp3',
        title: 'Titre',
        artist: 'Artiste',
        album: 'Album',
        duration: const Duration(minutes: 3),
        filePath: '/musique/a.mp3',
        coverPath: '/covers/123.jpg',
      );

      final json = track.toJson();

      expect(json['filePath'], '/musique/a.mp3');
      expect(json['coverPath'], '/covers/123.jpg');
      expect(json.containsKey('subsonicId'), isFalse);
      expect(Track.fromJson(json).filePath, '/musique/a.mp3');
    });

    test('un titre fantome (import CSV introuvable) reste un placeholder', () {
      final track = Track.fromJson({
        'id': 'missing:Titre:Artiste:Album',
        'title': 'Titre',
        'artist': 'Artiste',
        'album': 'Album',
        'duration': 0,
      });
      expect(track.isPlaceholder, isTrue);
      expect(track.toJson()['filePath'], isNull);
    });
  });

  group('migration du cache 1.2.0', () {
    late Map<String, dynamic> legacy;

    setUp(() {
      legacy = jsonDecode(
              File('test/fixtures/library_1_2_0.json').readAsStringSync())
          as Map<String, dynamic>;
    });

    test('les URL avec jeton du cache 1.2.0 deviennent des ids', () {
      final tracks = (legacy['navidromeTracks'] as List)
          .map((j) => Track.fromJson(j as Map<String, dynamic>))
          .toList();
      final albums = (legacy['albums'] as List)
          .map((j) => Album.fromJson(j as Map<String, dynamic>))
          .toList();
      final recents = (legacy['recentPlays'] as List)
          .map((j) => RecentPlay.fromJson(j as Map<String, dynamic>))
          .toList();

      expect(tracks.first.subsonicId, 'abc123');
      expect(tracks.first.coverArtId, 'abc123');
      // Les autres champs survivent a la migration.
      expect(tracks.first.isLiked, isTrue);
      expect(tracks.first.playCount, 4);

      _expectNoToken({
        'navidromeTracks': tracks.map((t) => t.toJson()).toList(),
        'albums': albums.map((a) => a.toJson()).toList(),
        'recentPlays': recents.map((r) => r.toJson()).toList(),
      });
    });

    test(
        'un titre synchronise hors connexion (URL vide) retrouve sa lecture via son id',
        () {
      final track = Track.fromJson(
          (legacy['navidromeTracks'] as List)[1] as Map<String, dynamic>);

      expect(track.subsonicId, 'hors-ligne');
      expect(track.filePath, contains('id=hors-ligne'));
      expect(track.isPlaceholder, isFalse);
    });

    test('pochette et lecture pointent sur l URL de la session en cours', () {
      final track = Track.fromJson(
          (legacy['navidromeTracks'] as List)[0] as Map<String, dynamic>);
      final album =
          Album.fromJson((legacy['albums'] as List)[0] as Map<String, dynamic>);

      expect(track.filePath, startsWith('https://nas.example/'));
      expect(album.coverPath,
          'https://nas.example/rest/getCoverArt.view?id=abc123&t=jeton&s=sel');
    });
  });

  group('SubsonicRefs', () {
    test('sans identifiants charges, une reference donne une URL vide', () {
      SubsonicRefs.coverUrlBuilder = null;
      expect(SubsonicRefs.resolve(SubsonicRefs.cover('1')), '');
    });

    test('une pochette externe (Deezer) n est pas prise pour du Subsonic', () {
      const deezer = 'https://e-cdns-images.dzcdn.net/images/cover/x/250.jpg';
      expect(SubsonicRefs.toStorable(deezer), deezer);
      expect(SubsonicRefs.coverIdOf(deezer), isNull);
    });

    test('l historique de recherche ne stocke plus l URL avec jeton', () {
      final item = SearchHistoryItem.track('Titre', 'navidrome_1', 'Artiste',
          imageUrl:
              'https://nas.example/rest/getCoverArt.view?id=1&u=x&t=jeton&s=sel');

      _expectNoToken(item.toJson());
      expect(item.imageUrl, contains('id=1'));
    });
  });
}
