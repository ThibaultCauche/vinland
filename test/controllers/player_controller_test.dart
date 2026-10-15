import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinland/controllers/playback_settings.dart';
import 'package:vinland/controllers/player_controller.dart';
import 'package:vinland/domain/replay_gain.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/player_engine.dart';

import '../fakes/fake_player_engine.dart';

void main() {
  final a = fakeTrack('a');
  final b = fakeTrack('b');
  final c = fakeTrack('c');
  final d = fakeTrack('d');
  final e = fakeTrack('e');
  final album = [a, b, c, d, e];

  late FakePlaybackOutput output;
  late FakePlayerEngine engine;
  late FakeTrackRepository repo;
  late PlayerController player;
  late List<String> started;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    output = FakePlaybackOutput();
    engine = output.engine;
    repo = FakeTrackRepository(album);
    started = [];
    player = PlayerController(output: output, tracks: repo)
      ..onTrackStarted = ((t) => started.add(t.id));
  });

  tearDown(() => player.dispose());

  group('fin de titre', () {
    test('passe au titre suivant de la file', () async {
      await player.playTrack(a, trackList: album);
      engine.emitCompleted();
      await pumpEventQueue();
      expect(player.currentTrack, b);
      expect(output.loadedTitles, ['a', 'b']);
      expect(repo.playsRecorded, ['a', 'b']);
      expect(started, ['a', 'b']);
    });

    test('un titre injouable est saute au lieu de bloquer la lecture',
        () async {
      output.failingTitles.add('b');
      await player.playTrack(a, trackList: album);
      engine.emitCompleted();
      await pumpEventQueue();
      expect(player.currentTrack, c);
      expect(output.loadedTitles, ['a', 'b', 'c']);
      expect(repo.playsRecorded, ['a', 'c'], reason: 'pas d\'ecoute notee');
    });

    test('reseau coupe : abandonne apres 3 echecs au lieu de vider la file',
        () async {
      output.failingTitles.addAll(['b', 'c', 'd', 'e']);
      await player.playTrack(a, trackList: album);
      engine.emitCompleted();
      await pumpEventQueue();
      expect(output.loadedTitles, ['a', 'b', 'c', 'd']);
      expect(player.queue.map((t) => t.id), ['e']);
    });

    test('repetition d\'un titre : le rejoue', () async {
      await player.toggleLoopMode(); // all
      await player.toggleLoopMode(); // one
      expect(player.loopMode, LoopMode.one);
      await player.playTrack(a, trackList: album);
      engine.emitCompleted();
      await pumpEventQueue();
      expect(player.currentTrack, a);
      expect(output.loadedTitles, ['a', 'a']);
    });

    test('dernier titre fini : reboucle sur le contexte lance', () async {
      await player.playTrack(e, trackList: album);
      engine.emitCompleted();
      await pumpEventQueue();
      expect(player.currentTrack, a);
    });

    test('plus rien apres dispose', () async {
      await player.playTrack(a, trackList: album);
      player.dispose();
      engine.emitCompleted();
      await pumpEventQueue();
      expect(output.loadedTitles, ['a']);
      player = PlayerController(output: output, tracks: repo); // tearDown
    });
  });

  group('filet de securite en fin de titre', () {
    // Les abonnements aux flux du moteur doivent naitre dans la zone
    // fakeAsync pour que le minuteur du filet y soit cree aussi.
    void inFakeZone(void Function(FakeAsync async) body) {
      fakeAsync((async) {
        player.dispose();
        player = PlayerController(output: output, tracks: repo);
        body(async);
      });
    }

    test('position figee en fin de titre : force le passage au suivant', () {
      inFakeZone((async) {
        unawaited(player.playTrack(a, trackList: album));
        async.elapse(const Duration(milliseconds: 1));
        expect(player.isPlaying, isTrue);
        engine.emitPosition(
            const Duration(minutes: 2, seconds: 59, milliseconds: 500));
        async.elapse(const Duration(seconds: 2, milliseconds: 1));
        expect(player.currentTrack, b);
      });
    });

    test('titre qui continue au-dela de sa duree annoncee : pas coupe', () {
      inFakeZone((async) {
        unawaited(player.playTrack(a, trackList: album));
        async.elapse(const Duration(milliseconds: 1));
        engine.emitPosition(
            const Duration(minutes: 2, seconds: 59, milliseconds: 500));
        async.elapse(const Duration(seconds: 1));
        engine.emitPosition(const Duration(minutes: 3, seconds: 1));
        async.elapse(const Duration(seconds: 2));
        expect(player.currentTrack, a);
      });
    });

    test('loin de la fin : le minuteur est desarme', () {
      inFakeZone((async) {
        unawaited(player.playTrack(a, trackList: album));
        async.elapse(const Duration(milliseconds: 1));
        engine.emitPosition(
            const Duration(minutes: 2, seconds: 59, milliseconds: 500));
        engine.emitPosition(const Duration(seconds: 10)); // seek en arriere
        async.elapse(const Duration(seconds: 3));
        expect(player.currentTrack, a);
      });
    });

    test('duree du titre inconnue : se fie a celle du moteur', () {
      final sansDuree = fakeTrack('x', duration: Duration.zero);
      inFakeZone((async) {
        unawaited(player.playTrack(sansDuree, trackList: [sansDuree, b]));
        async.elapse(const Duration(milliseconds: 1));
        engine.emitDuration(const Duration(minutes: 1));
        engine.emitPosition(const Duration(seconds: 59, milliseconds: 500));
        async.elapse(const Duration(seconds: 2, milliseconds: 1));
        expect(player.currentTrack, b);
      });
    });
  });

  group('lecture/pause', () {
    test(
        'pause au tout premier titre : un evenement "lecture" en retard du moteur '
        'ne remet pas le bouton sur lecture', () async {
      await player.playTrack(a, trackList: album);
      expect(player.isPlaying, isTrue);
      // Le moteur n'a pas encore emis son "playing=true" initial (warm-up du
      // codec + 1re connexion au NAS) quand l'utilisateur tape pause.
      expect(player.togglePlayPause(), isTrue);
      expect(player.isPlaying, isFalse);
      expect(output.calls, contains('pause'));

      engine.emitPlaying(true); // evenement en retard
      expect(player.isPlaying, isFalse);

      engine.emitPlaying(false); // le moteur rattrape l'ordre
      expect(player.isPlaying, isFalse);

      engine.emitPlaying(true); // vraie reprise externe (casque, voiture)
      expect(player.isPlaying, isTrue);
    });

    test(
        'pause pendant un chargement lent : le chargement qui finit apres ne '
        'remet pas le bouton sur lecture', () async {
      await player.playTrack(a, trackList: album);
      final slow = Completer<bool>();
      output.pendingLoads.add(slow);
      final loading = player.playTrack(c, trackList: album);
      await pumpEventQueue();
      player.togglePlayPause(); // isPlaying true -> false
      expect(player.isPlaying, isFalse);
      slow.complete(true);
      await loading;
      expect(player.isPlaying, isFalse);
      expect(player.currentTrack, c);
    });

    test(
        'seek pendant le chargement du titre : applique une fois charge, '
        'le titre ne repart pas du debut', () async {
      await player.playTrack(a, trackList: album);
      final slow = Completer<bool>();
      output.pendingLoads.add(slow);
      final loading = player.playTrack(c, trackList: album);
      await pumpEventQueue();
      player.seek(const Duration(seconds: 90));
      output.calls.clear();
      slow.complete(true);
      await loading;
      expect(output.calls, contains('seek:${const Duration(seconds: 90)}'));
    });

    test('seek pendant le chargement d\'un titre remplace ensuite : ignore',
        () async {
      await player.playTrack(a, trackList: album);
      final slow = Completer<bool>();
      output.pendingLoads.add(slow);
      final loading = player.playTrack(c, trackList: album);
      await pumpEventQueue();
      player.seek(const Duration(seconds: 90));
      slow.complete(true);
      output.calls.clear();
      await player.playTrack(b, trackList: album);
      await loading;
      expect(output.calls.where((c) => c.startsWith('seek:')), isEmpty);
    });

    test('apres un redemarrage de l\'app, play relance le dernier titre',
        () async {
      SharedPreferences.setMockInitialValues({'vinland_last_track_id': 'b'});
      await player.restore(await SharedPreferences.getInstance());
      expect(engine.hasSource, isFalse);
      expect(player.togglePlayPause(), isFalse);
      await pumpEventQueue();
      expect(output.loadedTitles, ['b']);
      expect(player.isPlaying, isTrue);
    });

    test('evenements du moteur relayes aux crochets', () async {
      var playingChanges = 0;
      var engineEvents = 0;
      player
        ..onPlayingChanged = (() => playingChanges++)
        ..onEngineEvent = (() => engineEvents++);
      engine.emitPlaying(true);
      engine.emitPlaying(true); // pas de changement
      engine.emitIndex(0);
      expect(playingChanges, 1);
      expect(engineEvents, 3);
      expect(player.isPlaying, isTrue);
    });

    test('seek et duree', () async {
      var notified = 0;
      player.addListener(() => notified++);
      player.seek(const Duration(seconds: 42));
      expect(output.calls, ['seek:0:00:42.000000']);
      engine.emitDuration(const Duration(minutes: 4));
      engine.emitDuration(const Duration(minutes: 4)); // identique : ignore
      expect(player.duration, const Duration(minutes: 4));
      expect(notified, 2);
      engine.emitPosition(const Duration(seconds: 7));
      expect(player.position, const Duration(seconds: 7));
      expect(notified, 2, reason: 'la position ne reconstruit pas l\'UI');
    });
  });

  group('suivant/precedent', () {
    test('precedent dans les 3 premieres secondes : titre d\'avant', () async {
      await player.playTrack(a, trackList: album);
      await player.next();
      expect(player.currentTrack, b);
      engine.emitPosition(const Duration(seconds: 2));
      await player.previous();
      expect(player.currentTrack, a);
      expect(player.queue.first, b);
    });

    test('precedent apres 3 secondes : redemarre le titre', () async {
      await player.playTrack(a, trackList: album);
      await player.next();
      engine.emitPosition(const Duration(seconds: 10));
      await player.previous();
      expect(player.currentTrack, b);
      expect(output.calls.last, 'seek:0:00:00.000000');
    });

    test('precedent sans historique : redemarre le titre', () async {
      await player.playTrack(a, trackList: album);
      await player.previous();
      expect(player.currentTrack, a);
      expect(output.calls.last, 'seek:0:00:00.000000');
    });

    test('lire depuis la file saute les titres intermediaires', () async {
      await player.playTrack(a, trackList: album);
      await player.playFromQueue(2);
      expect(player.currentTrack, d);
      expect(player.queue.map((t) => t.id), ['e']);
      await player.playFromQueue(9); // hors bornes
      expect(player.currentTrack, d);
    });

    test('un titre telecharge est lu depuis le fichier local', () async {
      repo.offline['a'] = '/hors-ligne/a.mp3';
      await player.playTrack(a);
      expect(player.currentTrack, a);
    });

    test(
        'un titre telecharge garde son adresse sur le serveur pour la '
        'Chromecast', () async {
      final nas = Track(
        id: 'n',
        title: 'n',
        artist: 'Artiste',
        album: 'Album',
        duration: const Duration(minutes: 3),
        filePath: 'https://nas.example/musique/n.mp3',
      );
      repo.offline['n'] = '/hors-ligne/n.mp3';
      await player.playTrack(nas);
      final item = output.loadedItems.single;
      expect(item.id, '/hors-ligne/n.mp3');
      expect(item.extras?['streamUrl'], 'https://nas.example/musique/n.mp3');
    });
  });

  group('file d\'attente', () {
    test('ajout, lire ensuite, retrait, reordonnancement sauvegardes',
        () async {
      await player.playTrack(a, trackList: [a, b]);
      player.addToQueue(c);
      player.playNext(d);
      player.removeFromQueue(1); // retire b
      player.removeFromQueue(7); // ignore
      player.reorderQueue(0, 1); // d apres c
      expect(player.queue.map((t) => t.id), ['c', 'd']);
      await pumpEventQueue();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('vinland_last_queue_ids'), ['c', 'd']);
    });

    test('file de l\'hote Jam : remplace la notre', () async {
      await player.playTrack(a, trackList: album);
      player.replaceQueue([e]);
      expect(player.queue, [e]);
    });

    test('aleatoire et repetition persistes', () async {
      await player.playTrack(a, trackList: album);
      await player.toggleShuffle();
      await player.toggleLoopMode();
      expect(player.isShuffled, isTrue);
      expect(player.isRepeatEnabled, isTrue);
      expect(player.queue.map((t) => t.id).toSet(), {'b', 'c', 'd', 'e'});
      await pumpEventQueue();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('vinland_shuffle_enabled'), isTrue);
      expect(prefs.getString('vinland_loop_mode'), 'all');
      await player.toggleLoopMode();
      await player.toggleLoopMode();
      expect(player.loopMode, LoopMode.off);
    });
  });

  group('sauvegarde de l\'etat de lecture', () {
    test('le titre lance est ecrit avant de signaler son demarrage', () async {
      String? savedWhenStarted;
      player.onTrackStarted = (_) async {
        savedWhenStarted = (await SharedPreferences.getInstance())
            .getString('vinland_last_track_id');
      };
      await player.playTrack(b, trackList: album);
      await pumpEventQueue();
      expect(savedWhenStarted, 'b');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('vinland_last_queue_ids'), ['c', 'd', 'e']);
      expect(prefs.getStringList('vinland_last_source_ids'),
          ['a', 'b', 'c', 'd', 'e']);
    });

    test('restaure titre, file, contexte et modes sans lancer la lecture',
        () async {
      SharedPreferences.setMockInitialValues({
        'vinland_last_track_id': 'b',
        'vinland_last_queue_ids': ['c', 'inconnu', 'd'],
        'vinland_last_source_ids': ['a', 'b', 'c', 'd'],
        'vinland_shuffle_enabled': true,
        'vinland_loop_mode': 'one',
      });
      Track? cover;
      player.onTrackLoading = (t) => cover = t;
      await player.restore(await SharedPreferences.getInstance());
      expect(player.currentTrack, b);
      expect(player.queue.map((t) => t.id), ['c', 'd']);
      expect(player.isShuffled, isTrue);
      expect(player.loopMode, LoopMode.one);
      expect(player.isPlaying, isFalse);
      expect(cover, b);
      expect(output.loadedTitles, isEmpty);
      // Le contexte restaure sert au rebouclage.
      await player.playFromQueue(1);
      await player.next();
      expect(player.currentTrack!.id, isNot('d'));
    });

    test('ancienne sauvegarde sans contexte : file + titre servent de contexte',
        () async {
      SharedPreferences.setMockInitialValues({
        'vinland_last_track_id': 'a',
        'vinland_last_queue_ids': ['b'],
        'vinland_loop_mode': 'inconnu',
      });
      await player.restore(await SharedPreferences.getInstance());
      expect(player.loopMode, LoopMode.off);
      await player.next(); // b
      await player.next(); // file vide : reboucle sur [a, b] sans b
      expect(player.currentTrack, a);
    });

    test('titre sauvegarde disparu de la bibliotheque : rien de restaure',
        () async {
      SharedPreferences.setMockInitialValues(
          {'vinland_last_track_id': 'supprime'});
      await player.restore(await SharedPreferences.getInstance());
      expect(player.currentTrack, isNull);
    });

    test(
        'deconnexion : arrete le son meme si le service audio plante, puis '
        'oublie tout', () async {
      await player.playTrack(a, trackList: album);
      output.stopThrows = true;
      await player.stopOutput();
      expect(output.calls, contains('stop'));
      await player.reset();
      expect(player.currentTrack, isNull);
      expect(player.isPlaying, isFalse);
      expect(player.queue, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('vinland_last_track_id'), isNull);
      expect(prefs.getStringList('vinland_last_queue_ids'), isNull);
    });
  });

  group('titre suivant prepare (prechargement, fondu)', () {
    Duration at(int min, int sec) => Duration(minutes: min, seconds: sec);

    PlayerController withSettings(PlaybackSettings settings) {
      player.dispose();
      return player =
          PlayerController(output: output, tracks: repo, settings: settings);
    }

    test('prepare le suivant pendant les 20 dernieres secondes seulement',
        () async {
      await player.playTrack(a, trackList: album);
      engine.emitPosition(at(2, 30));
      expect(output.preloaded, isEmpty, reason: 'encore 30 s');
      engine.emitPosition(at(2, 41));
      engine.emitPosition(at(2, 42));
      expect(output.preloaded, ['b'], reason: 'une seule fois');

      engine.emitCompleted();
      await pumpEventQueue();
      expect(output.loadedTitles, ['a', 'b']);
      expect(output.crossfades.last, Duration.zero,
          reason: 'sans fondu : enchaine a la fin, deja precharge');
    });

    test('fondu de 6 s : le suivant demarre 6 s avant la fin', () async {
      withSettings(PlaybackSettings(crossfade: const Duration(seconds: 6)));
      await player.playTrack(a, trackList: album);
      engine.emitPosition(at(2, 45));
      await pumpEventQueue(); // prechargement termine
      engine.emitPosition(at(2, 53));
      expect(output.loadedTitles, ['a'], reason: 'encore 7 s');
      engine.emitPosition(at(2, 54));
      await pumpEventQueue();
      expect(output.loadedTitles, ['a', 'b']);
      expect(output.crossfades.last, const Duration(seconds: 6));
      expect(player.currentTrack, b);
    });

    test('fondu : pas de bascule anticipee tant que le suivant n\'est pas pret',
        () async {
      withSettings(PlaybackSettings(crossfade: const Duration(seconds: 6)));
      output.preloadFails = true;
      await player.playTrack(a, trackList: album);
      engine.emitPosition(at(2, 45));
      await pumpEventQueue();
      engine.emitPosition(at(2, 57));
      await pumpEventQueue();
      expect(output.loadedTitles, ['a'],
          reason: 'chargement classique a la fin, comme avant');
    });

    test('album qui s\'enchaine (live, mix) : jamais de fondu entre ses pistes',
        () async {
      Track piste(String id, int n) => Track(
            id: id,
            title: id,
            artist: 'Artiste',
            album: 'Live',
            duration: const Duration(minutes: 3),
            filePath: '/musique/$id.mp3',
            albumId: 'live',
            trackNumber: n,
          );
      final live = [piste('l1', 1), piste('l2', 2)];
      repo = FakeTrackRepository(live);
      withSettings(PlaybackSettings(crossfade: const Duration(seconds: 6)));
      await player.playTrack(live[0], trackList: live);
      engine.emitPosition(at(2, 45));
      await pumpEventQueue();
      engine.emitPosition(at(2, 57));
      await pumpEventQueue();
      expect(output.preloaded, ['l2'], reason: 'precharge quand meme');
      expect(output.loadedTitles, ['l1'], reason: 'pas de fondu anticipe');
    });

    test('participant de Jam : ne change pas de titre avant l\'hote', () async {
      withSettings(PlaybackSettings(crossfade: const Duration(seconds: 6)));
      player.allowCrossfade = () => false;
      await player.playTrack(a, trackList: album);
      engine.emitPosition(at(2, 45));
      await pumpEventQueue();
      engine.emitPosition(at(2, 57));
      await pumpEventQueue();
      expect(output.loadedTitles, ['a']);
    });

    test('file modifiee apres le prechargement : annule et prepare le bon',
        () async {
      await player.playTrack(a, trackList: album);
      engine.emitPosition(at(2, 45));
      player.playNext(d);
      expect(output.preloadCancels, 1);
      engine.emitPosition(at(2, 46));
      expect(output.preloaded, ['b', 'd']);

      player.addToQueue(e); // ne change pas le suivant : rien a annuler
      expect(output.preloadCancels, 1);

      engine.emitCompleted();
      await pumpEventQueue();
      expect(player.currentTrack, d);
    });

    test(
        'aleatoire active ou titre retire pendant la fin : prechargement annule',
        () async {
      await player.playTrack(a, trackList: album);
      engine.emitPosition(at(2, 45));
      player.removeFromQueue(0);
      expect(output.preloadCancels, 1);
      engine.emitPosition(at(2, 46));
      expect(output.preloaded, ['b', 'c']);
    });

    test('repetition d\'un titre : rien a precharger', () async {
      await player.toggleLoopMode(); // all
      await player.toggleLoopMode(); // one
      await player.playTrack(a, trackList: album);
      engine.emitPosition(at(2, 45));
      expect(output.preloaded, isEmpty);
    });

    test('pendant un chargement : la position de l\'ancien titre est ignoree',
        () async {
      final slow = Completer<bool>();
      await player.playTrack(a, trackList: album);
      output.pendingLoads.add(slow);
      final loading = player.next();
      await pumpEventQueue();
      engine.emitPosition(at(2, 50)); // encore la position de a
      expect(output.preloaded, isEmpty,
          reason: 'sinon c, le suivant de b, serait precharge trop tot');
      slow.complete(true);
      await loading;
    });

    test(
        'ReplayGain : gain du titre transmis, et applique si le reglage change',
        () async {
      final loud = Track(
        id: 'fort',
        title: 'fort',
        artist: 'Artiste',
        album: 'Album',
        duration: const Duration(minutes: 3),
        filePath: '/musique/fort.mp3',
        replayGain: const ReplayGain(trackGain: -8),
      );
      final settings = PlaybackSettings();
      withSettings(settings);
      await player.playTrack(loud);
      expect(output.gains.last, 1.0, reason: 'desactive par defaut');
      await settings.setReplayGainMode(ReplayGainMode.track);
      expect(output.trackGainChanges.single, closeTo(0.398, 0.001));
      await player.playTrack(loud);
      expect(output.gains.last, closeTo(0.398, 0.001));
    });

    test('reglages relus et bornes (0 a 12 s)', () async {
      SharedPreferences.setMockInitialValues({
        'vinland_crossfade_seconds': 40,
        'vinland_replaygain_mode': 'album',
      });
      final settings = PlaybackSettings();
      await settings.load(await SharedPreferences.getInstance());
      expect(settings.crossfade, const Duration(seconds: 12));
      expect(settings.replayGainMode, ReplayGainMode.album);
      await settings.setCrossfade(const Duration(seconds: 3));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('vinland_crossfade_seconds'), 3);
    });
  });
}
