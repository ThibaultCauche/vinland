import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/services/local_track_matcher.dart';
import 'package:vinland/models/discovered_track.dart';
import 'package:vinland/models/track.dart';

Track _localTrack({
  required String title,
  required String artist,
  required String album,
}) =>
    Track(
      id: 'local-$title',
      title: title,
      artist: artist,
      album: album,
      duration: const Duration(minutes: 3),
      filePath: '/music/$title.mp3',
    );

DiscoveredTrack _discoveredTrack({
  required String title,
  required String artistName,
  required String albumName,
}) =>
    DiscoveredTrack(
      id: 1,
      title: title,
      artistName: artistName,
      albumName: albumName,
    );

void main() {
  group('findLocalTrackMatch', () {
    test(
        'trouve le titre local meme quand Deezer ne fournit pas '
        "d'artiste (bug reel : ces albums n'avaient jamais d'options "
        'meme quand le titre etait sur le NAS)', () {
      final local = [
        _localTrack(
            title: 'Kissing the machine',
            artist: '美波',
            album: 'Kissing the machine'),
      ];
      final discovered = _discoveredTrack(
        title: 'Kissing the machine',
        artistName: 'Inconnu',
        albumName: 'Inconnu',
      );

      expect(findLocalTrackMatch(discovered, local), isNotNull);
    });

    test('matche normalement quand l\'artiste Deezer est connu', () {
      final local = [
        _localTrack(title: 'One More Time', artist: 'Daft Punk', album: 'Discovery'),
      ];
      final discovered = _discoveredTrack(
        title: 'One More Time',
        artistName: 'Daft Punk',
        albumName: 'Discovery',
      );

      expect(findLocalTrackMatch(discovered, local), isNotNull);
    });

    test('ne matche pas un titre different meme si l\'artiste est inconnu',
        () {
      final local = [
        _localTrack(
            title: 'Un tout autre titre', artist: 'Un autre artiste', album: 'Inconnu'),
      ];
      final discovered = _discoveredTrack(
        title: 'Kissing the machine',
        artistName: 'Inconnu',
        albumName: 'Inconnu',
      );

      expect(findLocalTrackMatch(discovered, local), isNull);
    });
  });
}
