import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/domain/offline_playback.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/subsonic_refs.dart';

Track _nas(String id) => Track(
      id: 'navidrome_$id',
      title: id,
      artist: 'Artiste',
      album: 'Album',
      duration: const Duration(minutes: 3),
      filePath: SubsonicRefs.stream(id),
    );

Track _local(String id) => Track(
      id: id,
      title: id,
      artist: 'Artiste',
      album: 'Album',
      duration: const Duration(minutes: 3),
      filePath: '/musique/$id.mp3',
    );

void main() {
  group('isPlayableWithoutServer', () {
    test('titre du NAS : seulement s\'il est telecharge', () {
      expect(isPlayableWithoutServer(_nas('a'), downloaded: false), isFalse);
      expect(isPlayableWithoutServer(_nas('a'), downloaded: true), isTrue);
    });

    test('fichier local : toujours jouable', () {
      expect(isPlayableWithoutServer(_local('a'), downloaded: false), isTrue);
    });
  });

  group('firstPlayableFrom', () {
    final a = _nas('a'), b = _nas('b'), c = _nas('c'), d = _nas('d');
    final list = [a, b, c, d];

    test('le titre tape s\'il est jouable', () {
      expect(firstPlayableFrom(b, list, (_) => true), b);
    });

    test('sinon le premier jouable qui le suit', () {
      expect(firstPlayableFrom(b, list, (t) => t == d), d);
    });

    test('revient au debut de la liste', () {
      expect(firstPlayableFrom(c, list, (t) => t == a), a);
    });

    test('rien de jouable : null', () {
      expect(firstPlayableFrom(c, list, (_) => false), isNull);
    });

    test('titre absent de la liste : premier jouable de la liste', () {
      expect(firstPlayableFrom(_nas('x'), list, (t) => t == c), c);
    });
  });

  group('OfflineCollection', () {
    test('cles et ids', () {
      final album = OfflineCollection.album('al-1');
      final playlist = OfflineCollection.playlist('pl:2');
      expect(OfflineCollection.isAlbum(album), isTrue);
      expect(OfflineCollection.isPlaylist(album), isFalse);
      expect(OfflineCollection.idOf(album), 'al-1');
      expect(OfflineCollection.idOf(playlist), 'pl:2');
      expect(OfflineCollection.isAlbum(OfflineCollection.liked), isFalse);
    });
  });

  test('formatBytes', () {
    expect(formatBytes(0), '0 Mo');
    expect(formatBytes(500), '1 Ko');
    expect(formatBytes(850 * 1024 * 1024), '850 Mo');
    expect(formatBytes((1.25 * 1024 * 1024 * 1024).round()), '1,3 Go');
  });
}
