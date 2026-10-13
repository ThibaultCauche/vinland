import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/features/artist_discography/artist_discography_model.dart';
import 'package:vinland/features/friend_profile/friend_profile_model.dart';
import 'package:vinland/models/album.dart';
import 'package:vinland/models/discovered_artist.dart';
import 'package:vinland/models/friend_profile.dart';
import 'package:vinland/models/playlist.dart';
import 'package:vinland/models/recent_play.dart';

import '../fakes/fake_screen_deps.dart';

void main() {
  group('FriendProfileModel', () {
    final library = FakeLibrary(
        tracks: [track('t1', 'Voyager'), track('t2', 'Veridis Quo')]);
    final friend = FriendProfile(
      username: 'leo',
      likesPlaylist:
          Playlist(id: 'p1', name: 'Likes', trackIds: ['t2', 'absent', 't1']),
      nowPlayingTrackId: 't1',
    );
    final fetched = <String>[];
    final model = FriendProfileModel(
      friend: friend,
      library: library,
      fetchPlaylistIds: (id) async {
        fetched.add(id);
        return ['t1'];
      },
    );

    test('ne garde que les likes de l ami presents sur notre NAS', () {
      expect(model.likedTracks.map((t) => t.id), ['t2', 't1']);
      expect(model.recentTracks, isEmpty);
      expect(model.nowPlayingTrack?.id, 't1');
    });

    test('lire ses likes note l ami dans Recemment ecoute', () {
      model.playLikes();

      expect(library.played.last.$1.id, 't2');
      expect(library.recent.last.type, RecentPlayType.friend);
    });

    test('une playlist partagee sans titres charges les recupere a l ouverture',
        () async {
      final shared =
          Playlist(id: 'p2', name: 'Soiree', trackIds: [], serverId: 'srv-2');

      final opened = await model.playlistToOpen(shared);

      expect(fetched, ['srv-2']);
      expect(opened.trackIds, ['t1']);
      expect(opened.isPublic, isTrue);
    });
  });

  group('ArtistDiscographyModel', () {
    test('liste toutes les sorties puis charge leur tracklist', () async {
      final library = FakeLibrary(
        tracks: [track('t1', 'Da Funk', album: 'Homework')],
        albums: [
          Album(
              id: 'al-h',
              title: 'Homework',
              artist: 'Daft Punk',
              trackIds: ['t1'],
              year: 1997),
        ],
      );
      final discovery = FakeDiscovery()
        ..artistsByQuery['Daft Punk'] = [
          DiscoveredArtist(id: 27, name: 'Daft Punk')
        ]
        ..artistAlbums[27] = [
          deezerAlbum(11, 'Homework', releaseDate: '1997', isInLibrary: true),
          deezerAlbum(12, 'Discovery', releaseDate: '2001'),
        ]
        ..albumsById[11] = deezerAlbum(11, 'Homework', nbTracks: 16)
        ..albumTracks[11] = [
          deezerTrack(1, 'Da Funk', album: 'Homework'),
          deezerTrack(2, 'Revolution 909', album: 'Homework'),
        ]
        ..albumTracks[12] = [deezerTrack(3, 'One More Time')];

      final model = ArtistDiscographyModel(
          artistName: 'Daft Punk',
          discovery: discovery,
          library: library,
          downloadWorker: FakeDownloadWorker());
      await pumpEventQueue();

      expect(model.isLoading, isFalse);
      expect(model.entries.map((e) => e.local?.title ?? e.discovered!.title),
          ['Discovery', 'Homework']);
      expect(model.tracksOf(0)!.single.local, isNull);
      expect(model.tracksOf(1)!.map((t) => t.local?.id), ['t1', null]);
      model.dispose();
    });
  });
}
