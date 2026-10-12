import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vinland/data/subsonic/subsonic_client.dart';
import 'package:vinland/data/subsonic/subsonic_exception.dart';

import 'fake_subsonic_server.dart';

void main() {
  late FakeSubsonicServer server;
  late SubsonicClient client;

  setUp(() {
    server = FakeSubsonicServer();
    client = server.subsonicClient();
  });

  group('reponses du serveur', () {
    test('un ping accepte ne leve rien', () async {
      server.json('ping.view', fixture('ping_ok'));
      await client.ping();
      final url = server.requests.single.url;
      expect(url.path, '/rest/ping.view');
      expect(url.queryParameters, containsPair('f', 'json'));
      expect(url.queryParameters['u'], 'thibault');
      expect(url.queryParameters['c'], 'vinland');
    });

    test(
        'un refus Subsonic (HTTP 200, status failed) leve une erreur typee '
        'au lieu de passer pour un succes', () async {
      server.json('ping.view', fixture('error_wrong_credentials'));
      final error = await client.ping().then<Object?>((_) => null,
          onError: (Object e) => e) as SubsonicException?;
      expect(error, isNotNull);
      expect(error!.code, 40);
      expect(error.isAuthError, isTrue);
      expect(error.message, 'Wrong username or password');
      expect(error.toString(), contains('code 40'));
    });

    test('un like refuse par le serveur est une erreur', () async {
      server.json('star.view', fixture('error_not_found'));
      await expectLater(client.star(id: 'tr-1'),
          throwsA(isA<SubsonicException>().having((e) => e.code, 'code', 70)));
    });

    test('une page HTML (mauvaise URL, proxy) est une erreur, pas un crash',
        () async {
      server.on('ping.view', (_) => http.Response('<html></html>', 200));
      await expectLater(
          client.ping(),
          throwsA(isA<SubsonicException>()
              .having((e) => e.message, 'message', 'reponse non JSON')));
    });

    test('un code HTTP autre que 200 est une erreur', () async {
      server.on('ping.view', (_) => http.Response('oups', 502));
      await expectLater(
          client.ping(),
          throwsA(isA<SubsonicException>()
              .having((e) => e.httpStatus, 'httpStatus', 502)
              .having((e) => e.toString(), 'toString', contains('HTTP 502'))));
    });

    test('un JSON sans subsonic-response est une erreur', () async {
      server.json('ping.view', '{"autre": 1}');
      await expectLater(client.ping(), throwsA(isA<SubsonicException>()));
    });

    test('un refus sans detail garde un message lisible', () async {
      server.json('ping.view', '{"subsonic-response": {"status": "failed"}}');
      await expectLater(
          client.ping(),
          throwsA(isA<SubsonicException>()
              .having((e) => e.code, 'code', isNull)
              .having((e) => e.toString(), 'toString',
                  'SubsonicException: appel refuse par le serveur')));
    });

    test('sans serveur configure, aucun appel n est tente', () async {
      client.baseUrl = null;
      expect(() => client.uri('ping.view'), throwsA(isA<SubsonicException>()));
      expect(server.requests, isEmpty);
    });
  });

  group('erreurs reseau', () {
    test('une coupure passagere est reessayee', () async {
      var calls = 0;
      server.on('getStarred2.view', (_) {
        calls++;
        if (calls < 3) throw http.ClientException('handshake interrompu');
        return http.Response(fixture('starred2'), 200);
      });
      final starred = await client.starred2();
      expect(starred['song'], hasLength(1));
      expect(calls, 3);
      expect(client.requestCount, 3);
    });

    test('le delai entre les essais augmente', () async {
      final delays = <Duration>[];
      client = SubsonicClient(
        httpClient: server.client,
        sleep: (d) async => delays.add(d),
      )..baseUrl = 'https://nas.example';
      server.on(
          'getPlaylists.view', (_) => throw TimeoutException('NAS trop lent'));
      await expectLater(
          client.playlists(), throwsA(isA<SubsonicNetworkException>()));
      expect(delays, const [
        Duration(milliseconds: 400),
        Duration(milliseconds: 800),
      ]);
    });

    test('apres les essais, l erreur reseau remonte avec sa cause', () async {
      server.on('getPlaylists.view',
          (_) => throw http.ClientException('pas de reseau'));
      final error = await client
          .playlists()
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<SubsonicNetworkException>());
      expect(error.toString(), contains('pas de reseau'));
      expect(server.to('getPlaylists.view'), hasLength(3));
    });

    test('un refus Subsonic n est jamais reessaye', () async {
      server.json('getPlaylists.view', fixture('error_not_found'));
      await expectLater(client.playlists(), throwsA(isA<SubsonicException>()));
      expect(server.requests, hasLength(1));
    });

    test('creer une playlist n est pas reessaye (pas de doublon)', () async {
      server.on('createPlaylist.view',
          (_) => throw http.ClientException('reponse perdue'));
      await expectLater(client.createPlaylist('Soiree'),
          throwsA(isA<SubsonicNetworkException>()));
      expect(server.requests, hasLength(1));
    });

    test('un scrobble n est pas reessaye (pas de double ecoute)', () async {
      server.on('scrobble.view', (_) => throw http.ClientException('coupure'));
      await expectLater(
          client.scrobble('tr-1'), throwsA(isA<SubsonicNetworkException>()));
      expect(server.requests, hasLength(1));
    });
  });

  group('encodage', () {
    test('un pseudo avec & ne casse pas l URL', () async {
      client.authParams = const {'u': 'tom&jerry', 't': 'a+b', 's': 's=1'};
      server.json('ping.view', fixture('ping_ok'));
      await client.ping();
      final url = server.requests.single.url;
      expect(url.toString(), contains('u=tom%26jerry'));
      expect(url.queryParameters['u'], 'tom&jerry');
      expect(url.queryParameters['t'], 'a+b');
      expect(url.queryParameters['s'], 's=1');
    });

    test('une recherche avec espaces et accents est encodee', () async {
      server.json('search3.view', fixture('search3_songs'));
      await client.searchSongs('Café & Croissant');
      final url = server.requests.single.url;
      expect(url.queryParameters['query'], 'Café & Croissant');
      expect(url.queryParameters['songCount'], '20');
      expect(url.queryParameters['albumCount'], '0');
    });

    test('les extensions OpenSubsonic se lisent sans authentification',
        () async {
      server.json('getOpenSubsonicExtensions.view', fixture('extensions'));
      final extensions = await client.openSubsonicExtensions();
      expect(
          extensions.map((e) => e['name']), contains('apiKeyAuthentication'));
      final url = server.requests.single.url;
      expect(url.queryParameters.containsKey('u'), isFalse);
      expect(url.queryParameters.containsKey('t'), isFalse);
    });
  });

  group('pagination de la bibliotheque', () {
    test('tous les titres arrivent en pages de 500 via search3', () async {
      server.on('search3.view', (request) {
        final offset = int.parse(request.url.queryParameters['songOffset']!);
        final count = offset < 1000 ? 500 : 3;
        return http.Response(
            okResponse({
              'searchResult3': {'song': fakeSongs(count, from: offset)}
            }),
            200);
      });
      final pages = <int>[];
      final songs =
          await client.allSongs(onPage: (page) => pages.add(page.length));

      expect(songs, hasLength(1003));
      expect(pages, [500, 500, 3]);
      final requests = server.to('search3.view');
      expect(requests.map((r) => r.url.queryParameters['songOffset']),
          ['0', '500', '1000']);
      expect(requests.first.url.queryParameters['query'], '');
      expect(requests.first.url.queryParameters['songCount'], '500');
    });

    test('une page exactement pleine demande une page de plus, vide', () async {
      server.on('search3.view', (request) {
        final offset = int.parse(request.url.queryParameters['songOffset']!);
        return http.Response(
            okResponse({
              'searchResult3': offset == 0 ? {'song': fakeSongs(500)} : {}
            }),
            200);
      });
      final pages = <int>[];
      final songs =
          await client.allSongs(onPage: (page) => pages.add(page.length));
      expect(songs, hasLength(500));
      expect(pages, [500]);
    });

    test(
        'une page en erreur fait echouer la synchro au lieu de renvoyer une '
        'bibliotheque tronquee', () async {
      server.on('search3.view', (request) {
        final offset = int.parse(request.url.queryParameters['songOffset']!);
        if (offset == 500) {
          return http.Response(fixture('error_not_found'), 200);
        }
        return http.Response(
            okResponse({
              'searchResult3': {'song': fakeSongs(500, from: offset)}
            }),
            200);
      });
      await expectLater(client.allSongs(), throwsA(isA<SubsonicException>()));
    });

    test('tous les albums arrivent page par page', () async {
      server.on('getAlbumList2.view', (request) {
        final offset = int.parse(request.url.queryParameters['offset']!);
        final count = offset == 0 ? 500 : 2;
        return http.Response(
            okResponse({
              'albumList2': {
                'album': [
                  for (var i = offset; i < offset + count; i++)
                    {'id': 'al-$i', 'name': 'Album $i'}
                ]
              }
            }),
            200);
      });
      final albums = await client.allAlbums();
      expect(albums, hasLength(502));
      expect(server.to('getAlbumList2.view').first.url.queryParameters['type'],
          'alphabeticalByName');
    });
  });

  group('playlists', () {
    test(
        'modifier une grosse playlist passe en POST avec les titres dans le '
        'corps, pas dans l URL', () async {
      server.json('updatePlaylist.view', fixture('ping_ok'));
      final ids = [for (var i = 0; i < 2000; i++) 'tr-$i'];
      await client.updatePlaylist('pl-1',
          songIndexToRemove: const [1, 0], songIdToAdd: ids);

      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.headers['Content-Type'],
          startsWith('application/x-www-form-urlencoded'));
      expect(request.url.query, isEmpty);
      final body = Uri.splitQueryString(request.body);
      expect(body['playlistId'], 'pl-1');
      expect(body['u'], 'thibault');
      expect(body['f'], 'json');
      // Les parametres repetes sont tous presents, dans l'ordre.
      final added = RegExp(r'songIdToAdd=([^&]*)')
          .allMatches(request.body)
          .map((m) => m.group(1))
          .toList();
      expect(added, ids);
      expect(request.body, contains('songIndexToRemove=1&songIndexToRemove=0'));
    });

    test('changer le contenu d une playlist n est pas reessaye', () async {
      server.on('updatePlaylist.view',
          (_) => throw http.ClientException('reponse perdue'));
      await expectLater(client.updatePlaylist('pl-1', songIdToAdd: ['tr-1']),
          throwsA(isA<SubsonicNetworkException>()));
      expect(server.requests, hasLength(1));
    });

    test('changer seulement le nom ou le commentaire est reessaye', () async {
      var calls = 0;
      server.on('updatePlaylist.view', (_) {
        calls++;
        if (calls == 1) throw http.ClientException('coupure');
        return http.Response(fixture('ping_ok'), 200);
      });
      await client.updatePlaylist('pl-1',
          name: 'Soirée & co', comment: 'vinland:likes', public: true);
      final body = Uri.splitQueryString(server.requests.last.body);
      expect(body['name'], 'Soirée & co');
      expect(body['comment'], 'vinland:likes');
      expect(body['public'], 'true');
      expect(calls, 2);
    });

    test('lecture des playlists et de leur contenu', () async {
      server.json('getPlaylists.view', fixture('playlists'));
      server.json('getPlaylist.view', fixture('playlist'));
      final playlists = await client.playlists();
      expect(playlists.map((p) => p['id']), ['pl-1', 'pl-2']);
      final entries = await client.playlistEntries('pl-1');
      expect(entries.map((e) => e['id']), ['tr-1', 'tr-2']);
      expect(server.requests.last.url.queryParameters['id'], 'pl-1');
    });

    test('creation et suppression', () async {
      server.json('createPlaylist.view', fixture('create_playlist'));
      server.json('deletePlaylist.view', fixture('ping_ok'));
      expect(await client.createPlaylist('Nouvelle'), 'pl-9');
      await client.deletePlaylist('pl-9');
      expect(server.requests.last.url.queryParameters['id'], 'pl-9');
    });

    test('une playlist creee sans id est une erreur', () async {
      server.json('createPlaylist.view', okResponse());
      await expectLater(
          client.createPlaylist('Nouvelle'), throwsA(isA<SubsonicException>()));
    });
  });

  group('autres appels', () {
    test('like et unlike d un titre ou d un album', () async {
      server.json('star.view', fixture('ping_ok'));
      server.json('unstar.view', fixture('ping_ok'));
      await client.star(id: 'tr-1');
      await client.unstar(albumId: 'al-2');
      expect(server.requests[0].url.queryParameters['id'], 'tr-1');
      expect(server.requests[1].url.queryParameters['albumId'], 'al-2');
      expect(server.requests[1].url.queryParameters.containsKey('id'), isFalse);
    });

    test('titres et albums likes', () async {
      server.json('getStarred2.view', fixture('starred2'));
      final starred = await client.starred2();
      expect(starred['song']!.single['id'], 'tr-1');
      expect(starred['album']!.single['id'], 'al-2');
    });

    test('un album et ses titres', () async {
      server.json('getAlbum.view', fixture('album'));
      final album = await client.album('al-2');
      expect(album['name'], 'Discovery');
      expect(SubsonicClient.listOf(album['song']), hasLength(1));
    });

    test('un album absent de la reponse est une erreur', () async {
      server.json('getAlbum.view', okResponse());
      await expectLater(
          client.album('al-2'), throwsA(isA<SubsonicException>()));
    });

    test('derniers albums ajoutes', () async {
      server.json('getAlbumList2.view', fixture('album_list2'));
      final albums = await client.albumList2(type: 'newest', size: 5);
      expect(albums, hasLength(2));
      expect(server.requests.single.url.queryParameters['size'], '5');
    });

    test('scrobble envoie une ecoute terminee', () async {
      server.json('scrobble.view', fixture('ping_ok'));
      await client.scrobble('tr-1');
      expect(server.requests.single.url.queryParameters['submission'], 'true');
    });

    test('listOf accepte un objet seul ou rien', () {
      expect(SubsonicClient.listOf({'id': 1}), [
        {'id': 1}
      ]);
      expect(SubsonicClient.listOf(null), isEmpty);
      expect(
          SubsonicClient.listOf([
            'pas un objet',
            {'id': 2}
          ]),
          [
            {'id': 2}
          ]);
    });

    test('close ferme le client HTTP', () {
      client.close();
    });
  });
}
