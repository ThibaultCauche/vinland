import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinland/controllers/jam_controller.dart';
import 'package:vinland/controllers/player_controller.dart';
import 'package:vinland/models/track.dart';

import '../fakes/fake_jam_service.dart';
import '../fakes/fake_player_engine.dart';

final a = fakeTrack('a');
final b = fakeTrack('b');
final c = fakeTrack('c');
final d = fakeTrack('d');
final library = [a, b, c, d];

/// Un appareil complet (moteur, lecteur, Jam) branche comme dans AppState :
/// meme crochets, memes gardes devant chaque action de lecture.
class Device {
  Device(FakeJamRelay relay, String username, {String label = 'PC'})
      : jamService = FakeJamService(relay, username) {
    player = PlayerController(output: output, tracks: repo);
    jam = JamController(
      jam: jamService,
      playback: player,
      tracks: repo,
      username: () => username,
      deviceLabel: label,
    )..onHostingChanged = () => hostingChanges++;
    player
      ..onEngineEvent = jam.broadcastState
      ..onTrackStarted = (_) => jam.onLocalTrackStarted();
  }

  final output = FakePlaybackOutput();
  final repo = FakeTrackRepository(library);
  final FakeJamService jamService;
  late final PlayerController player;
  late final JamController jam;
  int hostingChanges = 0;

  FakePlayerEngine get engine => output.engine;

  // Facade d'AppState (voir playTrack/togglePlayPause/... dans app_state.dart).
  Future<void> play(Track t, {List<Track>? list}) async {
    if (jam.interceptPlayTrack(t)) return;
    await player.playTrack(t, trackList: list);
  }

  void toggle() {
    if (jam.interceptTogglePlayPause()) return;
    if (player.togglePlayPause()) jam.broadcastState();
  }

  Future<void> next() async {
    if (jam.interceptNext()) return;
    await player.next();
  }

  void seek(Duration pos) {
    if (jam.interceptSeek(pos)) return;
    player.seek(pos);
  }

  void addToQueue(Track t) {
    jam.relayAddToQueue(t);
    player.addToQueue(t);
  }

  void dispose() {
    jam.dispose();
    player.dispose();
  }
}

void main() {
  late FakeJamRelay relay;
  late List<Device> devices;

  Device device(String username, {String label = 'PC'}) {
    final dev = Device(relay, username, label: label);
    devices.add(dev);
    return dev;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    relay = FakeJamRelay();
    devices = [];
  });

  tearDown(() {
    for (final dev in devices) {
      dev.dispose();
    }
  });

  /// Ami qui suit un hote : `alice` heberge, `bob` a rejoint.
  Future<(Device, Device)> friendJam() async {
    final alice = device('alice');
    final bob = device('bob');
    final id = await alice.jam.startSession();
    expect(await bob.jam.joinSession(id!), isTrue);
    return (alice, bob);
  }

  group('suivre un hote', () {
    test('le participant joue le titre que l\'hote vient de lancer', () async {
      final (alice, bob) = await friendJam();
      await alice.play(b, list: library);
      await pumpEventQueue();

      expect(bob.player.currentTrack, b);
      expect(bob.output.loadedTitles, ['b']);
      expect(bob.player.queue.map((t) => t.id), ['c', 'd'],
          reason: 'la file affichee est celle de l\'hote');
    });

    test('l\'hote met en pause : le participant se met en pause aussi',
        () async {
      final (alice, bob) = await friendJam();
      await alice.play(a, list: library);
      await pumpEventQueue();
      alice.engine.emitPlaying(true);
      bob.engine.emitPlaying(true);
      bob.output.calls.clear();

      alice.toggle();
      await pumpEventQueue();

      expect(relay.relayedStates.last.isPlaying, isFalse);
      expect(bob.output.calls, contains('pause'));
    });

    test('le participant ne peut ni lancer ni mettre en pause en local',
        () async {
      final (alice, bob) = await friendJam();
      await alice.play(a, list: library);
      await pumpEventQueue();
      bob.output.loadedTitles.clear();
      bob.output.calls.clear();

      await bob.play(c);
      bob.toggle();
      await bob.next();

      expect(bob.output.loadedTitles, isEmpty);
      expect(bob.output.calls, isEmpty);
      expect(alice.player.currentTrack, a);
    });

    test('battement : l\'etat est rediffuse sans action de l\'hote', () {
      fakeAsync((async) {
        final alice = device('alice');
        final bob = device('bob');
        String? id;
        alice.jam.startSession().then((v) => id = v);
        async.flushMicrotasks();
        bob.jam.joinSession(id!);
        alice.play(a, list: library);
        // _playSingle attend un Future.delayed : il faut avancer l'horloge.
        async.elapse(Duration.zero);
        final before = relay.relayedStates.length;

        async.elapse(const Duration(seconds: 6));

        expect(relay.relayedStates.length, greaterThanOrEqualTo(before + 3));
      });
    });
  });

  group('commandes a distance', () {
    test('queue_add d\'un participant arrive dans la file de l\'hote',
        () async {
      final (alice, bob) = await friendJam();
      await alice.play(a, list: [a, b]);
      await pumpEventQueue();

      bob.addToQueue(d);
      await pumpEventQueue();

      expect(bob.jamService.sentCommands, ['queue_add:d']);
      expect(alice.player.queue.map((t) => t.id), ['b', 'd']);
      expect(bob.player.queue.map((t) => t.id), ['b', 'd'],
          reason: 'ajout local en attendant le prochain battement');
    });
  });

  group('hote parti', () {
    test('le participant quitte la session et reprend la main en local',
        () async {
      final (alice, bob) = await friendJam();
      await alice.play(a, list: library);
      await pumpEventQueue();

      await alice.jam.leaveSession();
      await pumpEventQueue();

      expect(bob.jam.isActive, isFalse);
      expect(relay.sessionIds, isEmpty);
      bob.output.loadedTitles.clear();
      await bob.play(c);
      expect(bob.output.loadedTitles, ['c'],
          reason: 'plus de garde de participant une fois l\'hote parti');
    });
  });

  group('transfert d\'hebergement', () {
    test('le nouvel hote diffuse, l\'ancien suit sans couper le son', () async {
      final (alice, bob) = await friendJam();
      await alice.play(a, list: library);
      await pumpEventQueue();
      expect(alice.jam.transferTargets, ['bob']);

      alice.jam.transferHost('bob');
      await pumpEventQueue();

      expect(bob.jam.isHost, isTrue);
      expect(alice.jam.isHost, isFalse);
      expect(alice.jam.isFriendJamActive, isTrue);
      expect(bob.output.loadedTitles, ['a'], reason: 'pas de rechargement');

      await bob.play(c, list: library);
      await pumpEventQueue();
      expect(alice.player.currentTrack, c);

      // L'ancien hote est maintenant un simple participant.
      alice.output.loadedTitles.clear();
      await alice.play(d);
      expect(alice.output.loadedTitles, isEmpty);
    });

    test('l\'ancien hote quitte la session quand le nouvel hote part',
        () async {
      final (alice, bob) = await friendJam();
      await alice.play(a, list: library);
      await pumpEventQueue();
      alice.jam.transferHost('bob');
      await pumpEventQueue();

      await bob.jam.leaveSession();
      await pumpEventQueue();

      expect(alice.jam.isActive, isFalse);
      alice.output.loadedTitles.clear();
      await alice.play(c);
      expect(alice.output.loadedTitles, ['c']);
    });

    test('un ami devenu hote voit son battement demarrer', () {
      fakeAsync((async) {
        final alice = device('alice');
        final bob = device('bob');
        String? id;
        alice.jam.startSession().then((v) => id = v);
        async.flushMicrotasks();
        bob.jam.joinSession(id!);
        alice.play(a, list: library);
        // _playSingle attend un Future.delayed : il faut avancer l'horloge.
        async.elapse(Duration.zero);
        alice.jam.transferHost('bob');
        async.flushMicrotasks();
        final before = relay.relayedStates.length;

        async.elapse(const Duration(seconds: 4));

        expect(relay.relayedStates.length, greaterThan(before));
        expect(relay.relayedStates.last.trackId, 'a');
      });
    });
  });

  group('synchro perso', () {
    /// Deux appareils du meme compte : le PC joue, le telephone suit.
    Future<(Device, Device)> personalSync() async {
      final pc = device('thibault', label: 'PC');
      final phone = device('thibault', label: 'Téléphone');
      await pc.play(a, list: library);
      await pumpEventQueue();
      expect(pc.jam.isPersonalSyncHost, isTrue);
      phone.jam.startPersonalSyncPolling();
      await pumpEventQueue();
      expect(phone.jam.isPersonalSyncParticipant, isTrue);
      return (pc, phone);
    }

    test('le participant affiche le titre de l\'hote sans jamais le jouer',
        () async {
      final (pc, phone) = await personalSync();
      pc.engine.emitPlaying(true);
      await pc.play(b, list: library);
      await pumpEventQueue();

      expect(phone.jam.remoteTrack, b);
      expect(phone.jam.remoteDeviceName, 'PC');
      expect(phone.output.loadedTitles, isEmpty);
      expect(phone.output.calls, isEmpty);
    });

    test('les boutons du telephone pilotent le PC', () async {
      final (pc, phone) = await personalSync();
      expect(pc.jam.connectedParticipantDeviceName, 'Téléphone');

      await phone.play(c);
      await pumpEventQueue();
      expect(pc.player.currentTrack, c);
      expect(phone.output.loadedTitles, isEmpty);

      phone.seek(const Duration(seconds: 42));
      expect(pc.output.calls, contains('seek:0:00:42.000000'));
      expect(phone.jam.remotePosition, const Duration(seconds: 42));
    });

    test(
        '"Reprendre ici" joue le titre sur cet appareil au lieu de le '
        'redemander a l\'hote', () async {
      final (pc, phone) = await personalSync();
      pc.player.position = const Duration(seconds: 30);
      pc.jam.broadcastState();

      await phone.jam.takeOverPersonalSync();
      await pumpEventQueue();

      expect(phone.output.loadedTitles, ['a']);
      expect(phone.output.calls, contains('seek:0:00:30.000000'));
      expect(phone.jam.isPersonalSyncHost, isTrue);
      expect(pc.jam.isPersonalSyncParticipant, isTrue,
          reason: 'le PC reste en synchro perso, pas en suiveur de Jam muet');
      expect(phone.jamService.sentCommands, isNot(contains('play_track:a')));
    });

    test(
        'un Jam entre amis ne se fait pas voler l\'hebergement par la '
        'synchro perso', () async {
      final alice = device('alice');
      final id = await alice.jam.startSession();
      await alice.play(a, list: library);
      await pumpEventQueue();

      expect(alice.jam.sessionId, id);
      expect(alice.jam.isFriendJamActive, isTrue);
      expect(alice.jam.isPersonalSyncHost, isFalse);
    });
  });

  test('deconnexion : la session est fermee et rien n\'est annonce', () async {
    final (alice, bob) = await friendJam();
    await alice.play(a, list: library);
    await pumpEventQueue();
    final changes = alice.hostingChanges;

    await alice.jam.disconnect();

    expect(alice.jam.isActive, isFalse);
    expect(alice.hostingChanges, changes);
    expect(bob.jam.isActive, isFalse);
  });

  test('relais injoignable : pas de session demarree', () async {
    final alice = device('alice');
    alice.jamService.unreachable = true;
    expect(await alice.jam.startSession(), isNull);
    expect(alice.jam.isActive, isFalse);
  });
}
