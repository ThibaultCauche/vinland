import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinland/controllers/jam_controller.dart';
import 'package:vinland/controllers/player_controller.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/personal_sync_secret.dart';

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
      // Meme compte = memes ids (voir PersonalSyncIds.fromAccountSecret) ;
      // seuls les appareils du compte connaissent le secret d'hebergement.
      personalSyncIds: (user) async =>
          PersonalSyncIds('perso-$user', 'secret-de-$user'),
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
      expect(relay.sessionIds, ['perso-alice'],
          reason: 'alice ecoute encore : seule sa synchro perso reste');
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
      relay.nowMs = 1000000;
      pc.engine.position = const Duration(seconds: 30);
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
        '"Reprendre ici" : l\'ancien appareil se tait, le nouveau repart '
        'la ou il en etait meme si le premier seek est ignore', () async {
      final (pc, phone) = await personalSync();
      pc.engine.emitPlaying(true);
      relay.nowMs = 1000000;
      pc.engine.position = const Duration(seconds: 30);
      pc.jam.broadcastState();
      relay.nowMs = 1000000 + 1500; // 1,5 s plus tard, on appuie
      phone.output.seeksToIgnore = 1;

      await phone.jam
          .takeOverPersonalSync(retryEvery: const Duration(milliseconds: 1));
      await pumpEventQueue();

      expect(phone.output.calls.where((c) => c == 'seek:0:00:31.500000'),
          hasLength(2),
          reason: 'le seek ignore est renvoye');
      expect(phone.engine.position, const Duration(milliseconds: 31500));
      expect(pc.output.calls.last, 'pause',
          reason: 'les deux appareils ne jouent plus en meme temps');
      expect(pc.jam.isPersonalSyncParticipant, isTrue);
    });

    test(
        'la soiree lance un titre sur le PC spectateur : il joue lui-meme et '
        'le telephone se met en pause', () async {
      final (phone, pc) = await personalSync();
      phone.engine.emitPlaying(true);
      await pumpEventQueue();

      // Ce que fait AppState._playPartyTrack : le lecteur directement.
      await pc.player.playTrack(c);
      await pumpEventQueue();

      expect(pc.output.loadedTitles, ['c']);
      expect(pc.jam.isPersonalSyncHost, isTrue);
      expect(phone.output.calls.last, 'pause');
    });

    test(
        'un appareil qui joue sa propre musique ne devient pas spectateur '
        'muet de l\'autre (ecran noir)', () async {
      final pc = device('thibault', label: 'PC');
      await pc.play(a, list: library);
      await pumpEventQueue();
      expect(pc.jam.isPersonalSyncHost, isTrue);
      // Le telephone suit le Jam d'un ami, qui s'arrete : sa musique continue.
      final ami = device('ami');
      final phone = device('thibault', label: 'Téléphone');
      final id = await ami.jam.startSession();
      await phone.jam.joinSession(id!);
      await ami.play(b, list: library);
      await pumpEventQueue();
      phone.engine.emitPlaying(true);

      await ami.jam.leaveSession();
      await pumpEventQueue();

      expect(phone.jam.isActive, isFalse);
      expect(phone.jam.isPersonalSyncParticipant, isFalse);
      expect(phone.player.currentTrack, b);
    });

    test(
        'quitter son Jam entre amis en pleine ecoute : les autres appareils '
        'du compte voient tout de suite la musique', () async {
      final phone = device('thibault', label: 'Téléphone');
      final ami = device('ami');
      final id = await phone.jam.startSession();
      await ami.jam.joinSession(id!);
      await phone.play(a, list: library);
      phone.engine.emitPlaying(true);
      await pumpEventQueue();
      expect(phone.jam.isPersonalSyncHost, isFalse);

      await phone.jam.leaveSession();
      await pumpEventQueue();
      expect(phone.jam.isPersonalSyncHost, isTrue);

      final pc = device('thibault', label: 'PC');
      pc.jam.startPersonalSyncPolling();
      await pumpEventQueue();
      expect(pc.jam.isPersonalSyncParticipant, isTrue);
      expect(pc.jam.remoteTrack, a);
    });

    test(
        'un ami qui connait le code de la synchro perso (mirroir « en '
        'cours ») ne peut pas en prendre l\'hebergement', () async {
      final (pc, _) = await personalSync();
      final ami = device('ami');

      expect(await ami.jamService.host('perso-thibault'), isFalse);
      expect(relay.refusedTakeovers, 1);
      expect(pc.jam.isPersonalSyncHost, isTrue);
      // Il peut toujours ecouter (ecoute a la demande).
      expect(await ami.jam.joinSession('perso-thibault'), isTrue);
    });

    test(
        'aucun autre appareil allume : le telephone espace ses tentatives '
        '(20 s, 40 s...) au lieu de frapper le relais toutes les 20 s', () {
      fakeAsync((async) {
        final phone = device('thibault', label: 'Téléphone');
        phone.jam.startPersonalSyncPolling();
        async.flushMicrotasks();
        expect(phone.jam.isActive, isFalse);
        async.elapse(const Duration(seconds: 20)); // 2e essai, rate

        final pc = device('thibault', label: 'PC');
        pc.play(a, list: library);
        async.elapse(Duration.zero);
        expect(pc.jam.isPersonalSyncHost, isTrue);

        async.elapse(const Duration(seconds: 39));
        expect(phone.jam.isActive, isFalse, reason: '3e essai a +40 s');
        async.elapse(const Duration(seconds: 1));
        expect(phone.jam.isPersonalSyncParticipant, isTrue);
      });
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

  group('rattrapage de l\'hote', () {
    const t0 = 1000000;

    /// alice joue `a` a 60 s, bob la suit et joue aussi.
    Future<(Device, Device)> listening() async {
      relay.nowMs = t0;
      final (alice, bob) = await friendJam();
      await alice.play(a, list: library);
      await pumpEventQueue();
      alice.engine.emitPlaying(true);
      bob.engine.emitPlaying(true);
      await pumpEventQueue();
      alice.engine.position = const Duration(seconds: 60);
      bob.engine.position = const Duration(seconds: 60);
      bob.output.calls.clear();
      bob.engine.log.clear();
      return (alice, bob);
    }

    test(
        'un retard de 200 ms ne coupe plus le son : la lecture accelere au '
        'lieu de faire un seek', () async {
      final (alice, bob) = await listening();
      bob.engine.position = const Duration(milliseconds: 59800);

      alice.jam.broadcastState();
      await pumpEventQueue();

      expect(bob.output.calls.where((c) => c.startsWith('seek')), isEmpty);
      expect(bob.engine.speed, closeTo(1.03, 1e-9));
      expect(bob.jam.syncLog.entries.last.driftMs, 200);
    });

    test('une fois rattrape, la vitesse redevient normale', () async {
      final (alice, bob) = await listening();
      bob.engine.position = const Duration(milliseconds: 59800);
      alice.jam.broadcastState();
      await pumpEventQueue();

      bob.engine.position = const Duration(seconds: 60);
      alice.jam.broadcastState();
      await pumpEventQueue();

      expect(bob.engine.speed, 1);
      expect(bob.output.calls.where((c) => c.startsWith('seek')), isEmpty);
    });

    test('plus d\'une seconde de retard : seek a la position de l\'hote',
        () async {
      final (alice, bob) = await listening();
      bob.engine.position = const Duration(seconds: 50);

      alice.jam.broadcastState();
      await pumpEventQueue();

      expect(bob.output.calls, contains('seek:0:01:00.000000'));
      expect(bob.engine.speed, 1);
    });

    test(
        'le temps de transit est compte en heure du relais : un participant '
        'deja a l\'heure ne ralentit pas', () async {
      final (alice, bob) = await listening();
      // L'etat met 500 ms a arriver : bob, qui joue deja 500 ms plus loin
      // que la position envoyee, est exactement aligne sur alice.
      relay.transitMs = 500;
      bob.engine.position = const Duration(milliseconds: 60500);

      alice.jam.broadcastState();
      await pumpEventQueue();

      expect(bob.engine.log, isNot(contains(startsWith('speed'))));
      expect(bob.output.calls.where((c) => c.startsWith('seek')), isEmpty);
      expect(bob.jam.syncLog.entries.last.driftMs, 0);
    });

    test(
        'decalage Bluetooth regle pendant l\'ecoute : l\'appareil se cale '
        'tout de suite en avance d\'autant', () async {
      final (alice, bob) = await listening();
      alice.jam.broadcastState();
      await pumpEventQueue();
      bob.output.calls.clear();

      await bob.jam.syncSettings.setOffset(const Duration(milliseconds: 200));
      await pumpEventQueue();

      expect(bob.output.calls, contains('seek:0:01:00.200000'));
    });

    test('l\'hote en Bluetooth annonce ce qu\'on entend vraiment chez lui',
        () async {
      final (alice, _) = await listening();
      await alice.jam.syncSettings.setOffset(const Duration(milliseconds: 150));

      alice.jam.broadcastState();

      expect(relay.relayedStates.last.positionMs, 59850);
    });

    test('quitter en plein rattrapage remet la vitesse normale', () async {
      final (alice, bob) = await listening();
      bob.engine.position = const Duration(milliseconds: 59800);
      alice.jam.broadcastState();
      await pumpEventQueue();
      expect(bob.engine.speed, isNot(1));

      await bob.jam.leaveSession();

      expect(bob.engine.speed, 1);
    });

    test('pas de rattrapage ni de journal quand l\'hote est en pause',
        () async {
      final (alice, bob) = await listening();
      alice.toggle();
      await pumpEventQueue();
      bob.engine.position = const Duration(milliseconds: 59800);
      bob.jam.syncLog.clear();

      alice.jam.broadcastState();
      await pumpEventQueue();

      expect(bob.engine.speed, 1);
      expect(bob.jam.syncLog.entries, isEmpty);
    });
  });
}
