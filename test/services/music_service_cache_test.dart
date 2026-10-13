import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:vinland/data/subsonic/subsonic_client.dart';
import 'package:vinland/models/recent_play.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/music_service.dart';
import 'package:vinland/services/navidrome_service.dart';

import '../subsonic/fake_subsonic_server.dart';

/// Scenario du plan de la session 13 : l'app est tuee pendant une synchro
/// de bibliotheque. On ne peut pas tuer le processus du test, donc on fait
/// comme Android : on abandonne l'instance en plein milieu (synchro bloquee
/// sur une page) et on relance une instance neuve sur les memes fichiers.
void main() {
  late Directory dir;

  /// Bloque la 2e page de titres tant qu'il n'est pas complete.
  Completer<void>? holdSecondPage;

  const totalSongs = 600;

  Future<NavidromeService> connectedNavidrome() async {
    final client = MockClient((request) async {
      final endpoint = request.url.pathSegments.last;
      switch (endpoint) {
        case 'ping.view':
          return http.Response(fixture('ping_ok'), 200);
        case 'getAlbumList2.view':
          return http.Response(fixture('album_list2'), 200);
        case 'search3.view':
          final offset =
              int.parse(request.url.queryParameters['songOffset'] ?? '0');
          if (offset > 0 && holdSecondPage != null) {
            await holdSecondPage!.future;
          }
          final count = (totalSongs - offset).clamp(0, 500);
          return http.Response(
              okResponse({
                'searchResult3': {'song': fakeSongs(count, from: offset)}
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

  Future<MusicService> launchApp() async {
    final music =
        MusicService(await connectedNavidrome(), storageRoot: () async => dir);
    music.setCurrentUser('u1');
    await music.initialize();
    return music;
  }

  Track trackOf(MusicService music, int i) =>
      music.allTracks.firstWhere((t) => t.id == 'navidrome_tr-$i');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vinland_music_cache_');
    holdSecondPage = null;
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test(
      'app tuee pendant une synchro : ni la bibliotheque ni les likes ni les '
      'ecoutes recentes ne sont perdus', () async {
    final first = await launchApp();
    expect(await first.syncWithNavidrome(), isTrue);
    expect(first.allTracks, hasLength(totalSongs));

    trackOf(first, 10)
      ..isLiked = true
      ..dateAdded = DateTime(2026, 9, 1);
    trackOf(first, 550)
      ..isLiked = true
      ..superLiked = true
      ..dateAdded = DateTime(2026, 9, 2);
    first.recordRecentPlay(RecentPlay(
      type: RecentPlayType.album,
      id: 'navidrome_al-1',
      title: 'Album 1',
      subtitle: 'Artiste',
      playedAt: DateTime(2026, 10, 1),
    ));
    await first.saveToCache();

    // Deuxieme synchro, bloquee apres la premiere page de 500 titres.
    holdSecondPage = Completer<void>();
    final firstBatch = Completer<void>();
    final sync = first.syncWithNavidrome(onProgress: () {
      if (!firstBatch.isCompleted) firstBatch.complete();
    });
    await firstBatch.future;
    expect(first.allTracks, hasLength(500));

    // Pendant la synchro : un like, puis une sauvegarde (debounce ou
    // saveToCache, peu importe), puis Android tue l'app.
    trackOf(first, 20)
      ..isLiked = true
      ..dateAdded = DateTime(2026, 9, 3);
    await first.saveToCache();

    final relaunched = await launchApp();
    expect(relaunched.allTracks, hasLength(totalSongs),
        reason: 'la bibliotheque a moitie recue ne doit pas remplacer la '
            'derniere complete');
    expect(trackOf(relaunched, 10).isLiked, isTrue);
    expect(trackOf(relaunched, 10).dateAdded, DateTime(2026, 9, 1));
    // Pas encore re-recu par la synchro interrompue : avant, son like
    // disparaissait avec la bibliotheque tronquee.
    expect(trackOf(relaunched, 550).isLiked, isTrue);
    expect(trackOf(relaunched, 550).superLiked, isTrue);
    expect(trackOf(relaunched, 550).dateAdded, DateTime(2026, 9, 2));
    expect(trackOf(relaunched, 20).isLiked, isTrue);
    expect(relaunched.recentPlays, hasLength(1));

    // La synchro de la premiere instance se termine sans rien casser.
    holdSecondPage!.complete();
    expect(await sync, isTrue);
    await first.saveToCache();
  });

  test('un like sur un titre absent de la bibliotheque revient a la synchro',
      () async {
    final first = await launchApp();
    await first.syncWithNavidrome();
    trackOf(first, 300)
      ..isLiked = true
      ..dateAdded = DateTime(2026, 9, 5);
    await first.saveToCache();

    // Fichier de bibliotheque perdu (et sa version precedente) : seules les
    // donnees perso restent.
    for (final f in Directory(p.join(dir.path, 'cache')).listSync()) {
      f.deleteSync();
    }
    final relaunched = await launchApp();
    expect(relaunched.allTracks, isEmpty);
    await relaunched.syncWithNavidrome();
    expect(trackOf(relaunched, 300).isLiked, isTrue);
    expect(trackOf(relaunched, 300).dateAdded, DateTime(2026, 9, 5));
    await relaunched.saveToCache();
  });

  test('cache 1.2 : decoupe au premier lancement, likes gardes, plus de jeton',
      () async {
    File(p.join(dir.path, 'cache', 'library_u1.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
          File('test/fixtures/library_1_2_0.json').readAsStringSync());

    final music = await launchApp();
    final liked = music.allTracks.firstWhere((t) => t.id == 'navidrome_abc123');
    expect(liked.isLiked, isTrue);
    expect(liked.playCount, 4);
    expect(liked.dateAdded, DateTime(2026, 9, 1, 10));
    expect(music.recentPlays, hasLength(1));

    final library =
        File(p.join(dir.path, 'cache', 'library_u1.json')).readAsStringSync();
    final userData = File(p.join(dir.path, 'userdata', 'userdata_u1.json'))
        .readAsStringSync();
    expect(library, isNot(contains('/rest/')));
    expect(userData, isNot(contains('/rest/')));
    expect((jsonDecode(library) as Map)['schemaVersion'], 2);
    expect((jsonDecode(userData) as Map)['trackStates'],
        contains('navidrome_abc123'));

    // Et le relancement suivant relit le nouveau format a l'identique.
    final again = await launchApp();
    final likedAgain =
        again.allTracks.firstWhere((t) => t.id == 'navidrome_abc123');
    expect(likedAgain.isLiked, isTrue);
    expect(likedAgain.playCount, 4);
  });

  test('les fichiers d un compte ne recoivent jamais les donnees d un autre',
      () async {
    final music = await launchApp();
    await music.syncWithNavidrome();
    trackOf(music, 1).isLiked = true;
    final save = music.saveToCache();
    music.setCurrentUser('u2');
    await save;
    expect(File(p.join(dir.path, 'userdata', 'userdata_u2.json')).existsSync(),
        isFalse);
    expect(File(p.join(dir.path, 'userdata', 'userdata_u1.json')).existsSync(),
        isTrue);
  });

  group('consentement de partage', () {
    test(
        'la reponse a la question de partage n\'est pas reposee au '
        'lancement suivant', () async {
      final first = await launchApp();
      expect(first.needsSharingConsent, isTrue,
          reason: 'nouveau compte : la question est posee');
      expect(first.shareLikesWithFriends, isFalse,
          reason: 'rien n\'est partage tant qu\'il n\'a pas repondu');
      await first.confirmSharingConsent(
          likes: true, recentPlays: false, nowPlaying: false);

      final relaunched = await launchApp();
      expect(relaunched.needsSharingConsent, isFalse);
      expect(relaunched.shareLikesWithFriends, isTrue);
      expect(relaunched.shareRecentPlaysWithFriends, isFalse);
    });

    test(
        'un compte 1.2.x garde ses partages apres la mise a jour mais on lui '
        'pose la question une fois', () async {
      final legacy = File(p.join(dir.path, 'cache', 'library_u1.json'));
      await legacy.create(recursive: true);
      await legacy.writeAsString(jsonEncode({
        'navidromeTracks': [],
        'albums': [],
        'playlists': [],
        'shareLikesWithFriends': true,
        'shareRecentPlaysWithFriends': true,
        'shareNowPlayingWithFriends': false,
      }));

      final music = await launchApp();
      expect(music.needsSharingConsent, isTrue);
      expect(music.shareLikesWithFriends, isTrue);
      expect(music.shareRecentPlaysWithFriends, isTrue);
      expect(music.shareNowPlayingWithFriends, isFalse);
    });
  });
}
