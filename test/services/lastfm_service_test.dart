import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/lastfm_service.dart';
import 'package:vinland/services/subsonic_refs.dart';

Track _t(String id, String artist, String title) => Track(
      id: id,
      title: title,
      artist: artist,
      album: 'Album',
      duration: const Duration(minutes: 3),
      filePath: SubsonicRefs.stream(id),
    );

void main() {
  test('tag.getTopTracks : artiste et titre de chaque titre', () async {
    late Uri asked;
    final service = LastfmService(
      apiKey: 'cle',
      client: MockClient((request) async {
        asked = request.url;
        return http.Response(
            jsonEncode({
              'tracks': {
                'track': [
                  {
                    'name': 'Someone Like You',
                    'artist': {'name': 'Adele'}
                  },
                ]
              }
            }),
            200);
      }),
    );
    expect(
        await service.topTracksForTag('sad'), [('Adele', 'Someone Like You')]);
    expect(asked.queryParameters['tag'], 'sad');
    expect(asked.queryParameters['method'], 'tag.gettoptracks');
  });

  test('sans cle, aucun appel', () async {
    final service = LastfmService(
        apiKey: '',
        client: MockClient((_) async => fail('pas d appel sans cle')));
    expect(service.isConfigured, isFalse);
    expect(await service.topTracksForTag('sad'), isEmpty);
  });

  test('seuls les titres de la bibliotheque sont gardes', () {
    final library = [
      _t('1', 'Adele', 'Someone Like You (Live)'),
      _t('2', 'Gotye/Kimbra', 'Somebody That I Used To Know'),
      _t('3', 'Autre', 'Someone Like You'),
    ];
    final found = matchInLibrary([
      ('Adele', 'Someone Like You'),
      ('Gotye', 'Somebody That I Used to Know'),
      ('Inconnu', 'Rien'),
    ], library);
    expect(found.map((t) => t.id).toSet(), {'1', '2'});
  });
}
