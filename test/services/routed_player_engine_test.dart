import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/services/audio_handler.dart';
import 'package:vinland/services/routed_player_engine.dart';

import '../fakes/fake_player_engine.dart';

void main() {
  group('RoutedPlayerEngine', () {
    test('relaie les flux du moteur actif seulement', () async {
      final local = FakePlayerEngine();
      final remote = FakePlayerEngine();
      final router = RoutedPlayerEngine(local);
      final playing = <bool>[];
      var completed = 0;
      router.playingStream.listen(playing.add);
      router.completedStream.listen((_) => completed++);

      local.emitPlaying(true);
      router.route(remote);
      local.emitCompleted(); // l'ancien moteur ne compte plus
      remote.emitCompleted();
      await Future<void>.delayed(Duration.zero);

      expect(router.isLocal, isFalse);
      expect(playing, [true, false]); // + etat du nouveau moteur
      expect(completed, 1);
    });

    test('les commandes vont au moteur actif', () async {
      final local = FakePlayerEngine();
      final remote = FakePlayerEngine();
      final router = RoutedPlayerEngine(local)..route(remote);
      await router.play();
      expect(remote.log, ['play']);
      expect(local.log, isEmpty);
    });
  });

  group('VinlandAudioHandler.switchOutput', () {
    late FakePlayerEngine local;
    late FakePlayerEngine remote;
    late VinlandAudioHandler handler;

    setUp(() async {
      local = FakePlayerEngine();
      remote = FakePlayerEngine();
      handler = VinlandAudioHandler(RoutedPlayerEngine(local));
      await handler.loadAndPlay([
        const MediaItem(id: 'http://nas/stream?id=1', title: 'Titre'),
      ], 0);
      local.emitPlaying(true);
      local.position = const Duration(seconds: 42);
      local.log.clear();
    });

    test('reprend le titre a la meme position sur la nouvelle sortie',
        () async {
      await handler.switchOutput(remote);
      expect(local.log, ['pause']);
      expect(remote.log, ['load:http://nas/stream?id=1', 'play']);
      expect(remote.position, const Duration(seconds: 42));
      expect(handler.activeEngine, same(remote));
    });

    test('retour sur l\'appareil en pause si demande', () async {
      await handler.switchOutput(remote);
      remote.position = const Duration(seconds: 50);
      await handler.switchOutput(local, resume: false);
      expect(local.log.last, 'load:http://nas/stream?id=1');
      expect(local.position, const Duration(seconds: 50));
      expect(handler.activeEngine, same(handler.localEngine));
    });

    test('un chargement refuse remonte l\'erreur', () async {
      remote.loadThrows = true;
      await expectLater(handler.switchOutput(remote), throwsStateError);
    });
  });
}
