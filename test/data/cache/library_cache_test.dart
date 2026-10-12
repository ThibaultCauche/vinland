import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vinland/data/cache/library_cache.dart';
import 'package:vinland/models/track.dart';

void main() {
  late Directory dir;
  late String libraryPath;
  late String userDataPath;

  LibraryCacheStore store() =>
      LibraryCacheStore(libraryPath: libraryPath, userDataPath: userDataPath);

  Map<String, dynamic> legacyFixture() => Map<String, dynamic>.from(
      jsonDecode(File('test/fixtures/library_1_2_0.json').readAsStringSync())
          as Map);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vinland_cache_');
    libraryPath = p.join(dir.path, 'cache', 'library_u1.json');
    userDataPath = p.join(dir.path, 'userdata', 'userdata_u1.json');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  group('migration du fichier unique (<= 1.3)', () {
    test('les likes, la date du like et les ecoutes passent en donnees perso',
        () {
      final user = userDataFromLegacy(legacyFixture());
      expect(user['schemaVersion'], userDataSchemaVersion);
      expect(user['recentPlays'], hasLength(1));
      final states = user['trackStates'] as Map;
      expect(states.keys, ['navidrome_abc123']);
      expect(states['navidrome_abc123'], {
        'isLiked': true,
        'superLiked': false,
        'dateAdded': '2026-09-01T10:00:00.000',
        'playCount': 4,
        'lastPlayed': null,
      });
    });

    test('la bibliotheque migree ne garde plus rien de perso', () {
      final library = upgradeLibraryCache(legacyFixture());
      expect(library['schemaVersion'], libraryCacheSchemaVersion);
      expect(library.containsKey('recentPlays'), isFalse);
      expect(library['albums'], hasLength(1));
      final first = (library['navidromeTracks'] as List).first as Map;
      expect(first['title'], 'Titre en cache');
      expect(first.containsKey('isLiked'), isFalse);
      expect(first.containsKey('dateAdded'), isFalse);
    });

    test('au premier chargement le vieux fichier est decoupe puis reecrit',
        () async {
      File(libraryPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(legacyFixture()));

      final loaded = await store().load();
      expect(loaded.needsRewrite, isTrue);
      expect(loaded.userData!['trackStates'], contains('navidrome_abc123'));
      expect(loaded.library!['navidromeTracks'], hasLength(2));

      await store().save(userData: loaded.userData!, library: loaded.library);
      final again = await store().load();
      expect(again.userData!['recentPlays'], hasLength(1));
      expect(again.userData!['trackStates'], contains('navidrome_abc123'));
      expect(again.library!['schemaVersion'], libraryCacheSchemaVersion);
    });

    test(
        'si les donnees perso existent deja (app tuee pendant la migration), '
        'elles gagnent sur le vieux fichier', () async {
      await store().save(userData: {
        'recentPlays': [],
        'trackStates': {
          'navidrome_abc123': {'isLiked': false, 'playCount': 9},
        },
      });
      File(libraryPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(legacyFixture()));

      final loaded = await store().load();
      expect(loaded.userData!['recentPlays'], isEmpty);
      expect(
          (loaded.userData!['trackStates'] as Map)['navidrome_abc123']
              ['playCount'],
          9);
    });
  });

  test('un fichier ecrit par une version plus recente est lu tel quel', () {
    final future = {'schemaVersion': 99, 'navidromeTracks': [], 'nouveau': 1};
    expect(upgradeLibraryCache(future), future);
    expect(upgradeUserData({'schemaVersion': 99, 'x': 1}),
        {'schemaVersion': 99, 'x': 1});
  });

  test('une synchro en cours ne reecrit que les donnees perso', () async {
    await store().save(
      userData: {'recentPlays': []},
      library: {
        'navidromeTracks': [
          {'id': 'navidrome_1'},
          {'id': 'navidrome_2'},
        ],
      },
    );
    final libraryBefore = File(libraryPath).readAsStringSync();

    await store().save(userData: {
      'recentPlays': [
        {'type': 'album', 'id': 'al-1', 'title': 'Album'}
      ]
    });

    expect(File(libraryPath).readAsStringSync(), libraryBefore);
    final loaded = await store().load();
    expect(loaded.userData!['recentPlays'], hasLength(1));
    expect(loaded.library!['navidromeTracks'], hasLength(2));
  });

  test(
      'donnees perso tronquees par un arret brutal : la version precedente '
      'est rechargee et le disque reecrit', () async {
    await store().save(userData: {
      'trackStates': {
        'navidrome_1': {'isLiked': true, 'dateAdded': '2026-01-01T00:00:00'},
      }
    });
    await store().save(userData: {
      'trackStates': {
        'navidrome_1': {'isLiked': true, 'dateAdded': '2026-01-01T00:00:00'},
        'navidrome_2': {'isLiked': true, 'dateAdded': '2026-01-02T00:00:00'},
      }
    });
    final full = File(userDataPath).readAsStringSync();
    File(userDataPath).writeAsStringSync(full.substring(0, full.length ~/ 2));

    final loaded = await store().load();
    expect(loaded.needsRewrite, isTrue);
    expect(loaded.userData!['trackStates'], contains('navidrome_1'));
  });

  group('etat perso d un titre', () {
    Track track() => Track(
          id: 'navidrome_1',
          title: 'T',
          artist: 'A',
          album: 'B',
          duration: Duration.zero,
        );

    test('un titre jamais like ni ecoute n est pas enregistre', () {
      expect(trackUserStateOf(track()), isNull);
    });

    test('aller-retour sans perte (like, date, super-like, ecoutes)', () {
      final t = track()
        ..isLiked = true
        ..superLiked = true
        ..dateAdded = DateTime(2026, 9, 1, 10)
        ..playCount = 3
        ..lastPlayed = DateTime(2026, 10, 1);
      final state =
          jsonDecode(jsonEncode(trackUserStateOf(t))) as Map<String, dynamic>;

      final copy = track()..playCount = 50;
      applyTrackUserState(copy, state);
      expect(copy.isLiked, isTrue);
      expect(copy.superLiked, isTrue);
      expect(copy.dateAdded, DateTime(2026, 9, 1, 10));
      expect(copy.playCount, 3);
      expect(copy.lastPlayed, DateTime(2026, 10, 1));

      final reconcile = trackUserStateForReconcile(state);
      expect(reconcile['dateAdded'], DateTime(2026, 9, 1, 10));
    });

    test('sans etat enregistre, le titre revient aux valeurs par defaut', () {
      final t = track()
        ..isLiked = true
        ..playCount = 2;
      applyTrackUserState(t, null);
      expect(t.isLiked, isFalse);
      expect(t.playCount, 0);
    });
  });
}
