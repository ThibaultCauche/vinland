import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/features/search/search_model.dart';
import 'package:vinland/models/album.dart';
import 'package:vinland/models/discovered_artist.dart';

import '../fakes/fake_screen_deps.dart';

void main() {
  late FakeLibrary library;
  late FakeDiscovery discovery;
  late FakeSearchHistory history;

  setUp(() {
    library = FakeLibrary(
      tracks: [track('t1', 'Digital Love')],
      albums: [
        Album(
            id: 'al-d',
            title: 'Discovery',
            artist: 'Daft Punk',
            trackIds: ['t1']),
      ],
    );
    discovery = FakeDiscovery()
      ..artistsByQuery['daft'] = [DiscoveredArtist(id: 27, name: 'Daft Punk')]
      ..albumsByQuery['daft'] = [
        deezerAlbum(10, 'Discovery'),
        deezerAlbum(11, 'Homework'),
      ]
      ..tracksByQuery['daft'] = [
        deezerTrack(1, 'Digital Love'),
        deezerTrack(2, 'Da Funk', album: 'Homework'),
      ];
    history = FakeSearchHistory();
  });

  SearchModel open({int albumLimit = 15}) => SearchModel(
        discovery: discovery,
        library: library,
        userId: 'thibault',
        history: history,
        downloadWorker: FakeDownloadWorker(),
        albumLimit: albumLimit,
      );

  test('attend la fin de la frappe avant de chercher', () {
    fakeAsync((async) {
      final model = open();
      model.onQueryChanged('da');
      async.elapse(const Duration(milliseconds: 200));
      model.onQueryChanged('daft');
      async.elapse(const Duration(milliseconds: 399));
      expect(model.query, isEmpty);

      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();

      expect(model.query, 'daft');
      expect(model.artists.single.name, 'Daft Punk');
      model.dispose();
    });
  });

  test('vider le champ efface les resultats et revient a l historique',
      () async {
    final model = open();
    await model.search('daft');

    model.onQueryChanged('  ');

    expect(model.query, isEmpty);
    expect(model.hasResults, isFalse);
    model.dispose();
  });

  test('un resultat Titres deja sur le NAS est relie au titre local', () async {
    final model = open();
    await model.search('daft');

    expect(model.tracks.map((t) => t.local?.id), ['t1', null]);
    expect(model.playableTracks.map((t) => t.id), ['t1']);
    model.dispose();
  });

  test('le desktop limite les albums a 12 resultats', () async {
    discovery.albumsByQuery['daft'] = [
      for (var i = 0; i < 20; i++) deezerAlbum(i, 'Album $i')
    ];
    final model = open(albumLimit: 12);
    await model.search('daft');

    expect(model.albums, hasLength(12));
    model.dispose();
  });

  test('un titre telecharge depuis la recherche devient lisible', () async {
    final model = open();
    await model.search('daft');
    library.arrivesOnDownload['Da Funk'] =
        track('t2', 'Da Funk', album: 'Homework');

    await model.downloadTrack(model.tracks[1].discovered, wait: doneAtOnce);

    expect(model.tracks[1].local?.id, 't2');
    model.dispose();
  });

  test('ouvrir un album deja sur le NAS ouvre la page album locale', () async {
    final model = open();
    await model.search('daft');

    expect(model.openAlbum(model.albums[0])?.id, 'al-d');
    expect(model.openAlbum(model.albums[1]), isNull);
    expect(history.items.map((i) => i.name), ['Homework', 'Discovery']);
    model.dispose();
  });

  test('l historique est propre a l utilisateur connecte', () async {
    final model = open();
    await pumpEventQueue();
    model.openArtist(DiscoveredArtist(id: 27, name: 'Daft Punk'));

    expect(history.user, 'thibault');
    await model.removeFromHistory(history.items.single);
    expect(model.history, isEmpty);
    model.dispose();
  });

  test('un titre de l historique est retrouve dans la bibliotheque', () async {
    final model = open();
    await model.rememberTrack(library.allTracks.single);

    expect(model.historyTrack(history.items.single)?.id, 't1');
    model.dispose();
  });
}
