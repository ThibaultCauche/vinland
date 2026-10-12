import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vinland/data/subsonic/subsonic_exception.dart';
import 'package:vinland/data/subsonic/subsonic_mappers.dart';
import 'package:vinland/services/navidrome_service.dart';

import 'fake_subsonic_server.dart';

void main() {
  late FakeSubsonicServer server;
  late NavidromeService navidrome;

  /// Service connecte (ping accepte) sur le faux serveur.
  Future<void> connect({String username = 'thibault'}) async {
    server.json('ping.view', fixture('ping_ok'));
    navidrome.debugSetCredentials('https://nas.example/', username, 'mdp');
    expect(await navidrome.authenticate(), isTrue);
    server.requests.clear();
  }

  setUp(() {
    server = FakeSubsonicServer();
    navidrome = NavidromeService.withClient(server.subsonicClient());
  });

  group('connexion', () {
    test('des identifiants refuses ne laissent pas l app connectee', () async {
      server.json('ping.view', fixture('error_wrong_credentials'));
      navidrome.debugSetCredentials('https://nas.example', 'thibault', 'faux');
      expect(await navidrome.authenticate(), isFalse);
      expect(navidrome.isConnected, isFalse);
      expect(navidrome.hasCredentials, isTrue);
    });

    test('le slash final de l URL du serveur est retire', () async {
      await connect();
      expect(navidrome.baseUrl, 'https://nas.example');
      await navidrome.starTrack('navidrome_tr-1');
      expect(server.requests.single.url.path, '/rest/star.view');
    });

    test('la cle d API remplace le jeton dans les appels', () async {
      server.json('ping.view', fixture('ping_ok'));
      navidrome.debugSetCredentials('https://nas.example', 'thibault', 'mdp',
          apiKey: 'cle-123');
      expect(await navidrome.authenticate(), isTrue);
      final params = server.requests.single.url.queryParameters;
      expect(params['apiKey'], 'cle-123');
      expect(params.containsKey('t'), isFalse);
      expect(navidrome.usesApiKey, isTrue);
    });

    test('le serveur annonce ou non la cle d API', () async {
      await connect();
      server.json('getOpenSubsonicExtensions.view', fixture('extensions'));
      expect(await navidrome.supportsApiKeyAuth(), isTrue);
      server.json('getOpenSubsonicExtensions.view', fixture('error_not_found'));
      expect(await navidrome.supportsApiKeyAuth(), isFalse);
    });

    test('sans connexion, rien n est envoye', () async {
      expect(await navidrome.starTrack('navidrome_tr-1'), isFalse);
      expect(await navidrome.fetchPlaylistsOrNull(), isNull);
      expect(await navidrome.fetchRecentAlbums(), isEmpty);
      expect(await navidrome.findTrack('a', 'b'), isNull);
      expect(await navidrome.fetchAlbumTracks('al-1'), isEmpty);
      expect(await navidrome.fetchStarredTrackIds(), isEmpty);
      expect(await navidrome.fetchStarredAlbumIds(), isEmpty);
      expect(await navidrome.fetchPlaylistSongIds('pl-1'), isEmpty);
      expect(await navidrome.createServerPlaylist('x'), isNull);
      expect(await navidrome.replacePlaylistSongs('pl-1', ['a']), isFalse);
      await navidrome.scrobble('navidrome_tr-1');
      await expectLater(
          navidrome.fetchAllTracks(), throwsA(isA<SubsonicException>()));
      expect(server.requests, isEmpty);
    });
  });

  group('URL de lecture', () {
    test('un pseudo avec & reste correct dans l URL de lecture', () async {
      await connect(username: 'tom&jerry');
      final url = Uri.parse(navidrome.getStreamUrl('tr 1'));
      expect(url.queryParameters['u'], 'tom&jerry');
      expect(url.queryParameters['id'], 'tr 1');
      expect(url.queryParameters['maxBitRate'], '192');
      final cover = Uri.parse(navidrome.getCoverUrl('al-1_0'));
      expect(cover.queryParameters['u'], 'tom&jerry');
    });
  });

  group('ecritures refusees', () {
    test(
        'un like refuse par le serveur (status failed) n est plus pris pour '
        'un succes', () async {
      await connect();
      server.json('star.view', fixture('error_not_found'));
      server.json('unstar.view', fixture('error_not_found'));
      expect(await navidrome.starTrack('navidrome_tr-1'), isFalse);
      expect(await navidrome.unstarTrack('navidrome_tr-1'), isFalse);
      expect(await navidrome.starAlbum('al-1'), isFalse);
      expect(await navidrome.unstarAlbum('al-1'), isFalse);
      expect(server.requests.first.url.queryParameters['id'], 'tr-1');
    });

    test('un like accepte renvoie vrai', () async {
      await connect();
      server.json('star.view', fixture('ping_ok'));
      expect(await navidrome.starAlbum('al-1'), isTrue);
    });

    test('renommer ou supprimer une playlist refusee renvoie faux', () async {
      await connect();
      server.json('updatePlaylist.view', fixture('error_not_found'));
      server.json('deletePlaylist.view', fixture('error_not_found'));
      expect(await navidrome.setPlaylistMeta('pl-1', name: 'x'), isFalse);
      expect(await navidrome.deleteServerPlaylist('pl-1'), isFalse);
    });
  });

  group('synchro de la bibliotheque', () {
    test(
        'la synchro complete passe par search3 : quelques requetes au lieu '
        'd un getAlbum par album', () async {
      await connect();
      // 1200 albums de 12 titres = 14 400 titres.
      server.on('getAlbumList2.view', (request) {
        final offset = int.parse(request.url.queryParameters['offset']!);
        final count = (1200 - offset).clamp(0, 500);
        return http.Response(
            okResponse({
              'albumList2': {
                'album': [
                  for (var i = offset; i < offset + count; i++)
                    {'id': 'al-$i', 'name': 'Album $i', 'artist': 'AA $i'}
                ]
              }
            }),
            200);
      });
      server.on('search3.view', (request) {
        final offset = int.parse(request.url.queryParameters['songOffset']!);
        final count = (14400 - offset).clamp(0, 500);
        return http.Response(
            okResponse({
              'searchResult3': {'song': fakeSongs(count, from: offset)}
            }),
            200);
      });

      var batches = 0;
      final tracks = await navidrome.fetchAllTracks(onBatch: (_) => batches++);

      expect(tracks, hasLength(14400));
      expect(batches, 29);
      // Avant : 3 pages d'albums + 1200 getAlbum = 1203 requetes.
      expect(server.requests, hasLength(3 + 29));
      expect(server.to('getAlbum.view'), isEmpty);
      // L'artiste de l'album vient de la liste des albums.
      expect(tracks[13].albumArtist, 'AA 1');
      expect(tracks[13].albumId, 'al-1');
    });

    test('une page en erreur fait echouer toute la synchro', () async {
      await connect();
      server.json('getAlbumList2.view', fixture('album_list2'));
      server.on('search3.view', (request) {
        final offset = int.parse(request.url.queryParameters['songOffset']!);
        if (offset > 0) throw http.ClientException('NAS coupe');
        return http.Response(
            okResponse({
              'searchResult3': {'song': fakeSongs(500)}
            }),
            200);
      });
      await expectLater(
          navidrome.fetchAllTracks(), throwsA(isA<SubsonicNetworkException>()));
    });

    test('un serveur sans recherche vide repasse album par album', () async {
      await connect();
      server.json('getAlbumList2.view', fixture('album_list2'));
      server.json('search3.view', okResponse({'searchResult3': {}}));
      server.json('getAlbum.view', fixture('album'));
      final tracks = await navidrome.fetchAllTracks();
      expect(server.to('getAlbum.view'), hasLength(2));
      expect(tracks, hasLength(2));
      expect(tracks.first.albumArtist, 'Various Artists');
    });

    test('titres de la fixture convertis en Track', () async {
      await connect();
      server.json('getAlbumList2.view', fixture('album_list2'));
      server.json('search3.view', fixture('search3_songs'));
      final tracks = await navidrome.fetchAllTracks();
      expect(tracks.map((t) => t.id),
          ['navidrome_tr-1', 'navidrome_tr-2', 'navidrome_tr-3']);
      final enemy = tracks.first;
      expect(enemy.title, 'Enemy');
      expect(enemy.isLiked, isTrue);
      expect(enemy.albumId, 'al-1');
      expect(enemy.albumArtist, 'Various Artists');
      expect(enemy.duration, const Duration(seconds: 173));
      expect(enemy.year, 2024);
      expect(enemy.genre, 'Soundtrack');
      expect(enemy.addedToServerAt, DateTime.utc(2026, 3, 2, 19, 4, 11, 123));
      // Duree recue en texte.
      expect(tracks.last.duration, const Duration(seconds: 320));
    });

    test('derniers albums et leurs titres', () async {
      await connect();
      server.json('getAlbumList2.view', fixture('album_list2'));
      server.json('getAlbum.view', fixture('album'));
      final albums = await navidrome.fetchRecentAlbums(count: 2);
      expect(albums.map((a) => a['artist']), ['Various Artists', 'Daft Punk']);
      final tracks =
          await navidrome.fetchAlbumTracks('al-2', albumArtist: 'Daft Punk');
      expect(tracks.single.albumArtist, 'Daft Punk');
      expect(tracks.single.albumId, 'al-2');
    });

    test('echecs de lecture : listes vides au lieu d un crash', () async {
      await connect();
      for (final endpoint in [
        'getAlbumList2.view',
        'getAlbum.view',
        'search3.view',
        'getStarred2.view',
        'getPlaylist.view',
        'scrobble.view',
      ]) {
        server.json(endpoint, fixture('error_not_found'));
      }
      expect(await navidrome.fetchRecentAlbums(), isEmpty);
      expect(await navidrome.fetchAlbumTracks('al-1'), isEmpty);
      expect(await navidrome.findTrack('Daft Punk', 'One More Time'), isNull);
      expect(await navidrome.fetchStarredTrackIds(), isEmpty);
      expect(await navidrome.fetchStarredAlbumIds(), isEmpty);
      expect(await navidrome.fetchPlaylistSongIds('pl-1'), isEmpty);
      await navidrome.scrobble('navidrome_tr-1');
    });
  });

  group('recherche et likes', () {
    test('findTrack retrouve un titre au matching flou', () async {
      await connect();
      server.json('search3.view', fixture('search3_songs'));
      final found = await navidrome.findTrack('daft punk', 'One More Time');
      expect(found?.id, 'navidrome_tr-3');
      expect(found?.albumId, 'al-2');
      expect(await navidrome.findTrack('Inconnu', 'Rien'), isNull);
    });

    test('titres et albums likes', () async {
      await connect();
      server.json('getStarred2.view', fixture('starred2'));
      final tracks = await navidrome.fetchStarredTrackIds();
      expect(tracks.keys, ['navidrome_tr-1']);
      expect(tracks['navidrome_tr-1'], DateTime.utc(2026, 4, 1, 10));
      expect(await navidrome.fetchStarredAlbumIds(), {'navidrome_al-2'});
    });

    test('scrobble envoie l id sans prefixe', () async {
      await connect();
      server.json('scrobble.view', fixture('ping_ok'));
      await navidrome.scrobble('navidrome_tr-1');
      expect(server.requests.single.url.queryParameters['id'], 'tr-1');
    });
  });

  group('playlists', () {
    test(
        'une coupure pendant la lecture des playlists renvoie null, pour ne '
        'pas recreer un miroir en double', () async {
      await connect();
      server.on('getPlaylists.view',
          (_) => throw http.ClientException('NAS injoignable'));
      expect(await navidrome.fetchPlaylistsOrNull(), isNull);
      expect(await navidrome.fetchPlaylists(), isEmpty);
    });

    test('playlists et contenu', () async {
      await connect();
      server.json('getPlaylists.view', fixture('playlists'));
      server.json('getPlaylist.view', fixture('playlist'));
      final playlists = await navidrome.fetchPlaylists();
      expect(playlists.first, {
        'id': 'pl-1',
        'name': 'Titres likes',
        'owner': 'thibault',
        'public': true,
        'comment': 'vinland:likes',
        'songCount': 2,
        'changed': '2026-04-01T10:00:00Z',
      });
      expect(await navidrome.fetchPlaylistSongIds('pl-1'),
          ['navidrome_tr-1', 'navidrome_tr-2']);
    });

    test('creer une playlist publique avec un commentaire', () async {
      await connect();
      server.json('createPlaylist.view', fixture('create_playlist'));
      server.json('updatePlaylist.view', fixture('ping_ok'));
      final id = await navidrome.createServerPlaylist('Nouvelle',
          comment: 'vinland:likes', public: true);
      expect(id, 'pl-9');
      final body = Uri.splitQueryString(server.requests.last.body);
      expect(body['comment'], 'vinland:likes');
      expect(body['public'], 'true');
    });

    test('une creation refusee renvoie null', () async {
      await connect();
      server.json('createPlaylist.view', fixture('error_not_found'));
      expect(await navidrome.createServerPlaylist('Nouvelle'), isNull);
    });

    test('remplacer le contenu d une playlist passe en un seul POST', () async {
      await connect();
      server.json('getPlaylist.view', fixture('playlist'));
      server.json('updatePlaylist.view', fixture('ping_ok'));
      final ids = [for (var i = 0; i < 800; i++) 'tr-$i'];
      expect(await navidrome.replacePlaylistSongs('pl-1', ids), isTrue);
      final update = server.to('updatePlaylist.view').single;
      expect(update.method, 'POST');
      expect(update.body, contains('songIndexToRemove=1&songIndexToRemove=0'));
      expect(RegExp('songIdToAdd=').allMatches(update.body), hasLength(800));
    });

    test('une playlist deja a jour n est pas reecrite', () async {
      await connect();
      server.json('getPlaylist.view', fixture('playlist'));
      expect(await navidrome.replacePlaylistSongs('pl-1', ['tr-1', 'tr-2']),
          isTrue);
      expect(server.to('updatePlaylist.view'), isEmpty);
    });

    test(
        'si le contenu actuel est illisible, les titres ne sont pas ajoutes '
        'par-dessus', () async {
      await connect();
      server.json('getPlaylist.view', fixture('error_not_found'));
      server.json('updatePlaylist.view', fixture('ping_ok'));
      expect(await navidrome.replacePlaylistSongs('pl-1', ['tr-3']), isFalse);
      expect(server.to('updatePlaylist.view'), isEmpty);
    });

    test('un remplacement refuse renvoie faux', () async {
      await connect();
      server.json('getPlaylist.view', fixture('playlist'));
      server.json('updatePlaylist.view', fixture('error_not_found'));
      expect(await navidrome.replacePlaylistSongs('pl-1', ['tr-3']), isFalse);
    });
  });

  test('resume d un album', () {
    expect(albumSummaryFromSubsonic({'id': 'al-1', 'name': 'A', 'extra': 1}),
        containsPair('name', 'A'));
  });
}
