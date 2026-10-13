import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/features/discovered_album/discovered_album_model.dart';
import 'package:vinland/services/download_worker_service.dart';

import '../fakes/fake_screen_deps.dart';

void main() {
  late FakeLibrary library;
  late FakeDiscovery discovery;
  late FakeDownloadWorker worker;

  setUp(() {
    library = FakeLibrary(tracks: [track('t1', 'Da Funk', album: 'Homework')]);
    discovery = FakeDiscovery()
      ..albumsById[11] = deezerAlbum(11, 'Homework', artist: 'Inconnu')
      ..albumTracks[11] = [
        deezerTrack(1, 'Da Funk', album: 'Homework'),
        deezerTrack(2, 'Revolution 909', album: 'Homework'),
        deezerTrack(3, 'Rollin\' & Scratchin\'', album: 'Homework'),
      ];
    worker = FakeDownloadWorker();
  });

  DiscoveredAlbumModel open() => DiscoveredAlbumModel(
      albumId: 11,
      discovery: discovery,
      library: library,
      downloadWorker: worker);

  test('ouvre un album par son id Deezer (historique, lien partage)', () async {
    final model = open();
    expect(model.isLoading, isTrue);
    await pumpEventQueue();

    expect(model.album?.title, 'Homework');
    expect(model.tracks, hasLength(3));
    model.dispose();
  });

  test('affiche l artiste des titres quand celui de l album est Inconnu',
      () async {
    final model = open();
    await pumpEventQueue();

    expect(model.artistName, 'Daft Punk');
    model.dispose();
  });

  test('relie les titres deja sur le NAS', () async {
    final model = open();
    await pumpEventQueue();

    expect(model.localMatches().values.map((t) => t?.id), ['t1', null, null]);
    model.dispose();
  });

  test('Telecharger lance tous les titres manquants sans popup', () async {
    final model = open();
    await pumpEventQueue();
    final matches = model.localMatches();
    final missing = model.tracks.where((t) => matches[t.id] == null);
    final wait = ManualWait();

    model.downloadMissing(missing, wait: wait.call);
    await pumpEventQueue();

    expect(worker.requests, hasLength(2));
    expect(model.downloadStateOf(2), DownloadUiState.downloading);
    expect(model.downloadStateOf(3), DownloadUiState.downloading);
    model.dispose();
  });

  test('l album "Inconnu" de Deezer n est pas envoye au worker', () async {
    final model = open();
    await pumpEventQueue();

    await model.downloadTrack(deezerTrack(9, 'Titre seul', album: 'Inconnu'),
        wait: doneAtOnce);

    expect(worker.requests, ['Daft Punk - Titre seul (sans album)']);
    model.dispose();
  });
}
