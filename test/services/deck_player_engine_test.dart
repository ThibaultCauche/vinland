import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/services/deck_player_engine.dart';
import 'package:vinland/services/player_engine.dart';

import '../fakes/fake_player_engine.dart';

PlayerQueueItem item(String path) =>
    PlayerQueueItem(path: path, isRemote: path.startsWith('http'));

void main() {
  late FakePlayerEngine a;
  late FakePlayerEngine b;
  late DeckPlayerEngine deck;
  late List<bool> playing;
  late int completed;

  setUp(() {
    a = FakePlayerEngine();
    b = FakePlayerEngine();
    deck = DeckPlayerEngine(a, b);
    playing = [];
    completed = 0;
    deck.playingStream.listen(playing.add);
    deck.completedStream.listen((_) => completed++);
  });

  Future<void> startOnA(String path) async {
    await deck.setAudioSources([item(path)], initialIndex: 0);
    await deck.play();
  }

  test('le titre suivant est charge sur l\'autre platine sans couper',
      () async {
    await startOnA('a.mp3');
    expect(await deck.preload(item('b.mp3')), isTrue);
    expect(b.log, ['load:b.mp3']);
    expect(a.log, ['load:a.mp3', 'play'], reason: 'a joue toujours');
    expect(deck.isPreloaded('b.mp3'), isTrue);
  });

  test('bascule sans blanc : b demarre, a s\'arrete, sans faux "pause"',
      () async {
    await startOnA('a.mp3');
    await deck.preload(item('b.mp3'));
    playing.clear();
    await deck.playPreloaded();
    await pumpEventQueue();
    expect(b.log.last, 'play');
    expect(a.log.last, 'stop');
    expect(playing, [true],
        reason: 'l\'arret de a ne doit pas faire croire a une pause');
    expect(deck.playing, isTrue);
  });

  test('fin de la platine sortante ignoree : la file n\'avance qu\'une fois',
      () async {
    await startOnA('a.mp3');
    await deck.preload(item('b.mp3'));
    await deck.playPreloaded(fade: const Duration(seconds: 6));
    a.emitCompleted(); // a finit pendant le fondu
    await pumpEventQueue();
    expect(completed, 0);
    b.emitCompleted();
    await pumpEventQueue();
    expect(completed, 1);
    await deck.stop(); // arrete le minuteur du fondu
  });

  test('positions : seule la platine active est relayee', () async {
    final positions = <Duration>[];
    deck.positionStream.listen(positions.add);
    await startOnA('a.mp3');
    await deck.preload(item('b.mp3'));
    b.emitPosition(const Duration(seconds: 1)); // ignore : b pas active
    a.emitPosition(const Duration(seconds: 170));
    await deck.playPreloaded();
    a.emitPosition(const Duration(seconds: 171)); // ignore : a sortie
    b.emitPosition(const Duration(seconds: 2));
    await pumpEventQueue();
    expect(positions, [
      const Duration(seconds: 170),
      const Duration(seconds: 1), // etat de b au moment de la bascule
      const Duration(seconds: 2),
    ]);
  });

  test('fondu : volumes croises puis titre sortant arrete', () {
    fakeAsync((async) {
      startOnA('a.mp3');
      async.flushMicrotasks();
      deck.preload(item('b.mp3'));
      async.flushMicrotasks();
      deck.playPreloaded(fade: const Duration(seconds: 4));
      async.flushMicrotasks();
      expect(b.volume, 0, reason: 'b demarre en silence');
      expect(a.volume, 1);

      async.elapse(const Duration(seconds: 2));
      // Puissance constante : les deux a ~70 % au milieu.
      expect(b.volume, closeTo(0.707, 0.01));
      expect(a.volume, closeTo(0.707, 0.01));
      expect(a.log.last, 'play', reason: 'a joue encore');

      async.elapse(const Duration(seconds: 2));
      expect(deck.isFading, isFalse);
      expect(b.volume, 1);
      expect(a.log.last, 'stop');
    });
  });

  test('pause pendant le fondu : le titre sortant est coupe tout de suite', () {
    fakeAsync((async) {
      startOnA('a.mp3');
      async.flushMicrotasks();
      deck.preload(item('b.mp3'));
      async.flushMicrotasks();
      deck.playPreloaded(fade: const Duration(seconds: 8));
      async.elapse(const Duration(seconds: 1));
      deck.pause();
      async.flushMicrotasks();
      expect(a.log.last, 'stop');
      expect(b.log.last, 'pause');
      expect(b.volume, 1);
      expect(deck.isFading, isFalse);
    });
  });

  test('ReplayGain et volume utilisateur se multiplient par platine', () async {
    await deck.setVolume(0.5); // curseur desktop
    await deck.setTrackGain(0.8);
    expect(a.volume, closeTo(0.4, 1e-9));
    await deck.preload(item('b.mp3'), gain: 0.6);
    expect(b.volume, closeTo(0.3, 1e-9));
    expect(deck.volume, 0.5, reason: 'le curseur affiche le volume choisi');
  });

  test('file changee : prechargement annule, platine liberee', () async {
    await startOnA('a.mp3');
    await deck.preload(item('b.mp3'));
    deck.cancelPreload();
    await pumpEventQueue();
    expect(deck.isPreloaded('b.mp3'), isFalse);
    expect(b.log.last, 'stop');
  });

  test('annule pendant le chargement (reseau lent) : jamais marque pret',
      () async {
    await startOnA('a.mp3');
    final slow = Completer<void>();
    b.pendingLoad = slow;
    final result = deck.preload(item('b.mp3'));
    deck.cancelPreload();
    slow.complete();
    expect(await result, isFalse);
    expect(deck.isPreloaded('b.mp3'), isFalse);
  });

  test('prechargement en echec : pas pret, erreur journalisee', () async {
    final errors = <String>[];
    deck.errorMessages.listen(errors.add);
    await startOnA('a.mp3');
    b.loadThrows = true;
    expect(await deck.preload(item('b.mp3')), isFalse);
    await pumpEventQueue();
    expect(deck.isPreloaded('b.mp3'), isFalse);
    expect(errors.single, startsWith('prechargement:'));
  });

  test('autre titre charge a la main : le precharge est abandonne', () async {
    await startOnA('a.mp3');
    await deck.preload(item('b.mp3'));
    await deck.setAudioSources([item('c.mp3')], initialIndex: 0);
    expect(deck.isPreloaded('b.mp3'), isFalse);
    expect(a.log.last, 'load:c.mp3', reason: 'reste sur la platine active');
  });

  test('stop arrete les deux platines', () async {
    await startOnA('a.mp3');
    await deck.preload(item('b.mp3'));
    await deck.stop();
    expect(a.log.last, 'stop');
    expect(b.log.last, 'stop');
    expect(deck.isPreloaded('b.mp3'), isFalse);
  });
}
