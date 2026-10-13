import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/features/album/album_model.dart';
import 'package:vinland/models/album.dart';
import 'package:vinland/services/download_worker_service.dart';

import '../fakes/fake_screen_deps.dart';

void main() {
  group('buildAlbumTrackItems', () {
    test('suit l ordre Deezer et marque les titres absents du NAS', () {
      final local = [track('a', 'One More Time'), track('b', 'Aerodynamic')];
      final items = buildAlbumTrackItems(local, [
        deezerTrack(1, 'One More Time'),
        deezerTrack(2, 'Aerodynamic'),
        deezerTrack(3, 'Digital Love'),
      ]);

      expect(items.map((i) => i.local?.id ?? 'manque ${i.discovered!.id}'),
          ['a', 'b', 'manque 3']);
    });

    test('ajoute a la fin les titres locaux absents du tracklist Deezer', () {
      final items = buildAlbumTrackItems(
        [track('a', 'One More Time'), track('x', 'Titre bonus')],
        [deezerTrack(1, 'One More Time')],
      );

      expect(items.map((i) => i.local!.id), ['a', 'x']);
    });

    test('rapproche un titre local a la ponctuation differente', () {
      final items = buildAlbumTrackItems(
        [track('a', 'Harder, Better, Faster, Stronger')],
        [deezerTrack(1, 'Harder Better Faster Stronger')],
      );

      expect(items.single.local?.id, 'a');
    });

    test('sans tracklist Deezer, montre seulement les titres locaux', () {
      final items = buildAlbumTrackItems([track('a', 'Voyager')], []);

      expect(items.single.local?.id, 'a');
    });
  });

  test('un doublon du NAS n apparait qu une fois, en gardant la version likee',
      () {
    final tracks = dedupByTitle([
      track('a', 'Voyager'),
      track('b', 'Voyager', isLiked: true),
      track('c', 'Veridis Quo'),
    ]);

    expect(tracks.map((t) => t.id), ['b', 'c']);
  });

  group('AlbumModel', () {
    late FakeLibrary library;
    late FakeDiscovery discovery;
    late FakeDownloadWorker worker;
    final album = Album(
        id: 'al-99', title: '99', artist: 'Daft Punk', trackIds: ['t1', 't2']);

    setUp(() {
      library = FakeLibrary(tracks: [
        track('t1', 'Zeta', album: '99'),
        track('t2', 'Alpha', album: '99'),
        // Autre album dont le titre CONTIENT "99" : la vue desktop
        // l'affichait dans l'album "99" (filtre par similarite de nom).
        track('t3', 'Intrus', album: '99 Nights (Edition Deluxe)'),
      ]);
      discovery = FakeDiscovery()
        ..albumsByQuery['99'] = [deezerAlbum(5, '99')]
        ..albumTracks[5] = [
          deezerTrack(50, 'Alpha'),
          deezerTrack(51, 'Zeta'),
          deezerTrack(52, 'Manquant'),
        ];
      worker = FakeDownloadWorker();
    });

    AlbumModel open() => AlbumModel(
        album: album,
        discovery: discovery,
        library: library,
        downloadWorker: worker);

    test(
        'la page album ne montre pas les titres d un autre album au nom proche',
        () {
      final model = open();

      expect(model.localTracks.map((t) => t.id), ['t2', 't1']);
      model.dispose();
    });

    test('attend la reponse Deezer avant d afficher la tracklist complete',
        () async {
      final model = open();
      expect(model.hasLoadedOnce, isFalse);

      await pumpEventQueue();

      expect(model.hasLoadedOnce, isTrue);
      expect(model.items(model.localTracks).map((i) => i.discovered?.title),
          [null, null, 'Manquant']);
      model.dispose();
    });

    test('recharge le tracklist a la fin d une synchro NAS', () async {
      final model = open();
      await pumpEventQueue();
      final callsBefore = discovery.albumTrackCalls;

      library.startSync();
      library.finishSync();
      await pumpEventQueue();

      expect(discovery.albumTrackCalls, callsBefore + 1);
      model.dispose();
    });

    test('un titre telecharge perd son icone et l album se recharge', () async {
      final model = open();
      await pumpEventQueue();
      final wait = ManualWait();
      final missing = model.items(model.localTracks).last.discovered!;
      library.arrivesOnDownload['Manquant'] =
          track('t4', 'Manquant', album: '99');

      final done = model.downloadTrack(missing, wait: wait.call);
      await pumpEventQueue();
      expect(model.downloadStateOf(missing.id), DownloadUiState.downloading);

      wait.finish(DownloadJobState.done);
      expect(await done, isTrue);

      expect(model.downloadStateOf(missing.id), isNull);
      expect(library.downloaded, ['Daft Punk - Manquant']);
      expect(worker.requests, ['Daft Punk - Manquant (Discovery)']);
      model.dispose();
    });

    test('un echec du worker laisse l icone en erreur', () async {
      final model = open();
      await pumpEventQueue();
      final missing = deezerTrack(52, 'Manquant');
      worker.unreachable = true;

      expect(await model.downloadTrack(missing, wait: doneAtOnce), isFalse);

      expect(model.downloadStateOf(52), DownloadUiState.failed);
      model.dispose();
    });

    test('fermer la page pendant un telechargement ne plante pas', () async {
      final model = open();
      await pumpEventQueue();
      final wait = ManualWait();
      final done =
          model.downloadTrack(deezerTrack(52, 'Manquant'), wait: wait.call);
      await pumpEventQueue();

      model.dispose();
      wait.finish(DownloadJobState.done);

      expect(await done, isFalse);
      expect(library.downloaded, isEmpty);
    });

    test('lire l album note l album dans Recemment ecoute', () {
      final model = open();

      model.playAll(model.localTracks);

      expect(library.played.single.$1.id, 't2');
      expect(library.recent.single.id, 'al-99');
      model.dispose();
    });
  });
}
