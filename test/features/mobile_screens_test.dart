import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/models/album.dart';
import 'package:vinland/models/discovered_artist.dart';
import 'package:vinland/screens/album_screen.dart';
import 'package:vinland/screens/artist_screen.dart';
import 'package:vinland/screens/discovered_album_screen.dart';
import 'package:vinland/screens/search_screen.dart';

import '../fakes/fake_app_state.dart';
import '../fakes/fake_screen_deps.dart';

/// Rendu de base des ecrans mobiles branches sur leurs view-models : les
/// donnees du modele arrivent bien jusqu'a l'ecran.
void main() {
  late FakeLibrary library;
  late FakeAppState state;
  late FakeDiscovery discovery;

  setUp(() {
    library = FakeLibrary(
      tracks: [
        track('t1', 'One More Time'),
        track('t2', 'Aerodynamic'),
      ],
      albums: [
        Album(
            id: 'al-d',
            title: 'Discovery',
            artist: 'Daft Punk',
            trackIds: ['t1', 't2'],
            year: 2001),
      ],
    );
    state = FakeAppState(library);
    discovery = FakeDiscovery()
      ..artistsByQuery['Daft Punk'] = [
        DiscoveredArtist(id: 27, name: 'Daft Punk')
      ]
      ..topTracks[27] = [deezerTrack(1, 'One More Time')]
      ..artistAlbums[27] = [deezerAlbum(10, 'Homework', releaseDate: '1997')]
      ..albumsByQuery['Discovery'] = [deezerAlbum(20, 'Discovery')]
      ..albumTracks[20] = [
        deezerTrack(21, 'One More Time'),
        deezerTrack(22, 'Aerodynamic'),
        deezerTrack(23, 'Digital Love'),
      ]
      ..albumsById[30] = deezerAlbum(30, 'Homework')
      ..albumTracks[30] = [deezerTrack(31, 'Da Funk', album: 'Homework')];
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    // Ecran de telephone haut : toutes les sections sont construites.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(hostScreen(screen, state: state, discovery: discovery));
    await tester.pumpAndSettle();
  }

  testWidgets('page artiste : titres populaires, albums et titres du NAS',
      (tester) async {
    await show(tester, const ArtistScreen(artistName: 'Daft Punk'));

    expect(find.text('Titres populaires'), findsOneWidget);
    expect(find.text('2 titres locaux'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Dans le NAS'), findsOneWidget);
  });

  testWidgets('page album : le titre manquant du NAS est liste',
      (tester) async {
    await show(tester, AlbumScreen(album: library.albums.single));

    expect(find.text('Aerodynamic'), findsOneWidget);
    expect(find.text('Digital Love'), findsOneWidget);
  });

  testWidgets('page album Deezer : tracklist et artiste', (tester) async {
    await show(tester, DiscoveredAlbumScreen.fromAlbumId(30));

    expect(find.text('Homework'), findsOneWidget);
    expect(find.text('Da Funk'), findsOneWidget);
  });

  testWidgets('recherche : historique vide puis invitation a chercher',
      (tester) async {
    await show(tester, const SearchScreen());

    expect(find.text('Recherchez un artiste, un album ou un titre'),
        findsOneWidget);
  });
}
