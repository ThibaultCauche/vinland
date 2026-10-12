import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/features/artist/artist_model.dart';
import 'package:vinland/models/album.dart';
import 'package:vinland/models/discovered_artist.dart';
import 'package:vinland/models/recent_play.dart';

import '../fakes/fake_screen_deps.dart';

void main() {
  late FakeLibrary library;
  late FakeDiscovery discovery;

  setUp(() {
    library = FakeLibrary(
      tracks: [
        track('t1', 'One More Time', album: 'Discovery'),
        track('t2', 'Get Lucky', album: 'Random Access Memories'),
        track('x', 'Autre', artist: 'Justice', album: 'Cross'),
      ],
      albums: [
        Album(
            id: 'al-d',
            title: 'Discovery',
            artist: 'Daft Punk',
            trackIds: ['t1'],
            year: 2001),
        Album(id: 'al-c', title: 'Cross', artist: 'Justice', trackIds: ['x']),
      ],
    );
    discovery = FakeDiscovery()
      ..artistsByQuery['Daft Punk'] = [
        DiscoveredArtist(id: 27, name: 'Daft Punk', pictureBigUrl: 'photo')
      ]
      ..topTracks[27] = [
        deezerTrack(1, 'Get Lucky (Radio Edit)'),
        deezerTrack(2, 'Around the World'),
      ]
      ..artistAlbums[27] = [
        deezerAlbum(10, 'Discovery',
            releaseDate: '2001-03-12', nbTracks: 14, isInLibrary: true),
        deezerAlbum(11, 'Homework', releaseDate: '1997-01-20'),
        deezerAlbum(12, 'Human After All', releaseDate: '2005-03-14'),
      ]
      ..albumsById[10] = deezerAlbum(10, 'Discovery', nbTracks: 14);
  });

  ArtistModel open({int? deepMatchLimit}) => ArtistModel(
        artistName: 'Daft Punk',
        discovery: discovery,
        library: library,
        downloadWorker: FakeDownloadWorker(),
        deepMatchLimit: deepMatchLimit,
      );

  test('ne garde que les titres et albums locaux de l artiste', () {
    final model = open();

    expect(model.local.tracks.map((t) => t.id), ['t1', 't2']);
    expect(model.local.albums.map((a) => a.id), ['al-d']);
    model.dispose();
  });

  test('relie chaque titre populaire a son equivalent sur le NAS', () async {
    final model = open();
    expect(model.isLoading, isTrue);
    await pumpEventQueue();

    expect(model.isLoading, isFalse);
    expect(model.popularTracks.map((p) => p.local?.id), ['t2', null]);
    model.dispose();
  });

  test('fusionne albums locaux et Deezer du plus recent au plus ancien',
      () async {
    final model = open();
    await pumpEventQueue();

    final entries = model.albumEntries;
    expect(
        entries.map((e) => e.local?.title ?? 'deezer ${e.discovered!.title}'),
        ['deezer Human After All', 'Discovery', 'deezer Homework']);
    // Nombre de titres reel de l'album, pas le nombre deja telecharge (1).
    expect(entries[1].trackCount, 14);
    model.dispose();
  });

  test('rouvrir la page ne refait pas la recherche Deezer', () async {
    final first = open();
    await pumpEventQueue();
    first.dispose();

    final second = open();
    expect(second.isLoading, isFalse);
    expect(second.popularTracks, hasLength(2));
    expect(discovery.searchArtistCalls, 1);
    second.dispose();
  });

  test('la fin d une synchro NAS relance le calcul du statut possede',
      () async {
    final model = open();
    await pumpEventQueue();

    library.startSync();
    library.finishSync();
    await pumpEventQueue();

    expect(discovery.searchArtistCalls, 2);
    model.dispose();
  });

  test('ne verifie titre par titre que les albums de l apercu', () async {
    final model = open(deepMatchLimit: 1);
    await pumpEventQueue();

    // Seul le premier album affiche (Human After All) est verifie.
    expect(discovery.albumTrackCalls, 1);
    model.dispose();
  });

  test('lire l artiste note sa page dans Recemment ecoute avec sa photo',
      () async {
    final model = open();
    await pumpEventQueue();

    model.playAll();

    expect(library.played.single.$2?.map((t) => t.id), ['t1', 't2']);
    expect(library.recent.single.type, RecentPlayType.artist);
    expect(library.recent.single.coverPath, 'photo');
    model.dispose();
  });

  test('un titre populaire absent du NAS ne se lance pas', () async {
    final model = open();
    await pumpEventQueue();

    model.playPopular(model.popularTracks[1]);

    expect(library.played, isEmpty);
    model.dispose();
  });
}
