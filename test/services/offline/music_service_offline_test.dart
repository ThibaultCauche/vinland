import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinland/data/subsonic/subsonic_client.dart';
import 'package:vinland/domain/offline_playback.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/music_service.dart';
import 'package:vinland/services/navidrome_service.dart';
import 'package:vinland/services/offline/offline_covers.dart';
import 'package:vinland/services/offline/offline_downloader.dart';

import '../../subsonic/fake_subsonic_server.dart';

/// Telechargements hors-ligne de MusicService, avec un faux Navidrome :
/// titres + pochettes sur le disque, persistance au redemarrage, nettoyage.
void main() {
  late Directory dir;

  /// Titres que le faux NAS refuse de servir.
  late Set<String> failingIds;

  /// Debits demandes au NAS, par titre.
  late Map<String, String?> requestedBitRates;

  final songs = [
    for (var i = 0; i < 4; i++)
      {
        'id': 'tr-$i',
        'title': 'Titre $i',
        'artist': 'Artiste',
        'album': 'Album ${i ~/ 2}',
        'albumId': 'al-${i ~/ 2}',
        'coverArt': 'al-${i ~/ 2}',
        'duration': 200,
      }
  ];

  Future<NavidromeService> connectedNavidrome() async {
    final client = MockClient((request) async {
      switch (request.url.pathSegments.last) {
        case 'ping.view':
          return http.Response(fixture('ping_ok'), 200);
        case 'getAlbumList2.view':
          return http.Response(fixture('album_list2'), 200);
        case 'search3.view':
          final offset =
              int.parse(request.url.queryParameters['songOffset'] ?? '0');
          return http.Response(
              okResponse({
                'searchResult3': {'song': offset == 0 ? songs : []}
              }),
              200);
      }
      return http.Response('<html>introuvable</html>', 404);
    });
    final navidrome = NavidromeService.withClient(SubsonicClient(
      httpClient: client,
      maxRetries: 0,
      sleep: (_) async {},
    ));
    navidrome.debugSetCredentials('https://nas.example', 'thibault', 'mdp');
    expect(await navidrome.authenticate(), isTrue);
    return navidrome;
  }

  /// Faux NAS pour les fichiers : un flux mp3 ou une image.
  OfflineDownloader fakeFiles() =>
      OfflineDownloader(client: MockClient.streaming((request, _) async {
        final id = request.url.queryParameters['id']!;
        final endpoint = request.url.pathSegments.last;
        if (endpoint == 'stream.view') {
          requestedBitRates[id] = request.url.queryParameters['maxBitRate'];
        }
        if (failingIds.contains(id)) {
          return http.StreamedResponse(Stream.fromIterable([]), 500);
        }
        final body = endpoint == 'stream.view' ? 'mp3:$id' : 'img:$id';
        return http.StreamedResponse(
          Stream.fromIterable([body.codeUnits]),
          200,
          headers: {
            'content-type':
                endpoint == 'stream.view' ? 'audio/mpeg' : 'image/jpeg',
          },
        );
      }));

  Future<MusicService> launchApp() async {
    final music =
        MusicService(await connectedNavidrome(), storageRoot: () async => dir)
          ..offlineDownloader = fakeFiles();
    music.setCurrentUser('u1');
    await music.initialize();
    if (music.allTracks.isEmpty) await music.syncWithNavidrome();
    return music;
  }

  Track trackOf(MusicService music, int i) =>
      music.allTracks.firstWhere((t) => t.id == 'navidrome_tr-$i');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vinland_offline_music_');
    failingIds = {};
    requestedBitRates = {};
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('telecharge titres et pochettes, compte les echecs', () async {
    final music = await launchApp();
    failingIds.add('tr-3');
    final progress = <double>[];
    final failed = await music.downloadTracks(
      [for (var i = 0; i < 4; i++) trackOf(music, i)],
      onProgress: progress.add,
    );

    expect(failed, 1);
    expect(progress, hasLength(4));
    expect(progress.last, 1.0);
    for (var i = 0; i < 3; i++) {
      final path = music.getOfflinePath('navidrome_tr-$i')!;
      expect(await File(path).readAsString(), 'mp3:tr-$i');
      expect(p(path), startsWith(p(dir.path)),
          reason: 'dans le dossier de l\'app, pas dans Documents');
    }
    expect(music.isTrackDownloaded('navidrome_tr-3'), isFalse);
    expect(
        await File(OfflineCovers.pathFor('al-0')!).readAsString(), 'img:al-0');
    expect(OfflineCovers.pathFor('al-1'), isNotNull);
    expect(requestedBitRates['tr-0'], '192');
    expect(await music.offlineBytes(), greaterThan(0));
  });

  test(
      'qualite choisie, collections suivies et fichiers : gardes au '
      'redemarrage', () async {
    final first = await launchApp();
    first.setOfflineBitRate(320);
    first.setOfflineCollection(OfflineCollection.album('al-0'), true);
    await first.downloadTracks([trackOf(first, 0)]);
    expect(requestedBitRates['tr-0'], '320');
    await first.saveToCache();

    final relaunched = await launchApp();
    await pumpEventQueue();
    expect(relaunched.offlineBitRateKbps, 320);
    expect(relaunched.isTrackDownloaded('navidrome_tr-0'), isTrue);
    expect(relaunched.isOfflineCollection(OfflineCollection.album('al-0')),
        isTrue);
    expect(OfflineCovers.pathFor('al-0'), isNotNull);
  });

  test('un fichier disparu du disque n\'est plus compte comme telecharge',
      () async {
    final first = await launchApp();
    await first.downloadTracks([trackOf(first, 0), trackOf(first, 1)]);
    await first.saveToCache();
    await File(first.getOfflinePath('navidrome_tr-0')!).delete();

    final relaunched = await launchApp();
    await pumpEventQueue(times: 50);
    expect(relaunched.isTrackDownloaded('navidrome_tr-0'), isFalse);
    expect(relaunched.isTrackDownloaded('navidrome_tr-1'), isTrue);
  });

  test('supprimer : la pochette part avec le dernier titre qui l\'utilise',
      () async {
    final music = await launchApp();
    await music.downloadTracks([trackOf(music, 0), trackOf(music, 1)]);
    final cover = OfflineCovers.pathFor('al-0')!;

    await music.removeDownloads([trackOf(music, 0)]);
    expect(music.isTrackDownloaded('navidrome_tr-0'), isFalse);
    expect(await File(cover).exists(), isTrue, reason: 'encore utilisee');

    await music.removeDownloads([trackOf(music, 1)]);
    expect(await File(cover).exists(), isFalse);
    expect(OfflineCovers.pathFor('al-0'), isNull);
  });

  test('tout supprimer vide aussi les collections suivies', () async {
    final music = await launchApp();
    music.setOfflineCollection(OfflineCollection.liked, true);
    await music.downloadTracks([trackOf(music, 0)]);
    final path = music.getOfflinePath('navidrome_tr-0')!;

    await music.removeAllDownloads();
    expect(music.downloadedTrackIds, isEmpty);
    expect(music.offlineCollections, isEmpty);
    expect(await File(path).exists(), isFalse);
  });
}

/// Chemin normalise pour comparer des prefixes.
String p(String path) => File(path).absolute.path;
