// Blind test : preparation des manches cote hote (sans reseau), puis une
// partie complete contre la vraie logique du relais (en memoire).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/controllers/blind_test_host.dart';
import 'package:vinland/controllers/party_controller.dart';
import 'package:vinland/controllers/party_host_dj.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/party/party_models.dart';
import 'package:vinland/services/subsonic_refs.dart';

import '../fakes/hub_party_socket.dart';

const relayUrl = 'wss://nas.test/jam';

Track _t(String id, String artist,
        {String? genre, int plays = 0, int seconds = 200}) =>
    Track(
      id: 'navidrome_$id',
      title: 'Titre $id',
      artist: artist,
      album: 'Album',
      duration: Duration(seconds: seconds),
      filePath: SubsonicRefs.stream(id),
      genre: genre,
      playCount: plays,
    );

final _library = [
  _t('1', 'Muse', genre: 'Rock', plays: 3),
  _t('2', 'Muse', genre: 'Rock'),
  _t('3', 'Daft Punk', genre: 'Électro', plays: 1),
  _t('4', 'Air', genre: 'Électro'),
  _t('5', 'Justice', genre: 'Électro'),
  _t('6', 'Queen', genre: 'Rock'),
  _t('7', 'Nirvana', genre: 'Rock'),
  _t('court', 'Intro', seconds: 30),
];

class FakeRelay implements BlindTestRelay {
  @override
  BlindTestState? blindTest;
  final sent = <String>[];
  final rounds = <({List<String> choices, int answer, PartySong song})>[];

  @override
  void startBlindTest(int rounds) => sent.add('start $rounds');
  @override
  void sendBlindTestRound({
    required List<String> choices,
    required int answer,
    required Duration duration,
    required PartySong song,
  }) {
    sent.add('round');
    rounds.add((choices: choices, answer: answer, song: song));
  }

  @override
  void revealBlindTest() => sent.add('reveal');
  @override
  void stopBlindTest() => sent.add('stop');
  @override
  void closeBlindTest() => sent.add('close');
}

class FakePlayback implements BlindTestPlayback {
  final played = <(String, Duration)>[];
  @override
  Future<void> playExtract(Track track, Duration from) async =>
      played.add((track.id, from));
}

void main() {
  late FakeRelay relay;
  late FakePlayback playback;
  late List<bool> djSuspended;
  late BlindTestHost host;

  setUp(() {
    relay = FakeRelay();
    playback = FakePlayback();
    djSuspended = [];
    host = BlindTestHost(
      relay: relay,
      playback: playback,
      library: () => _library,
      setDjSuspended: djSuspended.add,
      random: Random(1),
    );
  });

  tearDown(() => host.dispose());

  group('preparation', () {
    test('4 choix dont le bon, leurres d autres artistes', () {
      for (final q in host.prepare(5)) {
        expect(q.choices, hasLength(4));
        expect(q.choices[q.answer], BlindTestHost.label(q.track));
        final artists = q.choices.map((c) => c.split(' · ').last).toSet();
        expect(artists, hasLength(4), reason: '${q.choices}');
      }
    });

    test('un artiste par manche tant que possible, titres trop courts exclus',
        () {
      final questions = host.prepare(6);
      expect(questions.map((q) => q.track.artist).toSet(), hasLength(6));
      expect(questions.any((q) => q.track.id == 'navidrome_court'), isFalse);
    });

    test('titres deja ecoutes d abord', () {
      final first = host.prepare(2).map((q) => q.track.id).toSet();
      expect(first, {'navidrome_1', 'navidrome_3'});
    });

    test('leurres du meme genre quand il y en a', () {
      final q = host.prepare(7).firstWhere((q) => q.track.id == 'navidrome_6');
      // Queen (Rock) : leurres parmi Muse et Nirvana (Rock) d'abord.
      expect(
          q.choices.where((c) => c.contains('Muse') || c.contains('Nirvana')),
          hasLength(2));
    });

    test('bibliotheque trop petite : pas de blind test', () {
      expect(BlindTestHost.canPlay(_library.take(2).toList()), isFalse);
      expect(BlindTestHost.canPlay(_library), isTrue);
    });

    test('extrait vers le tiers du titre, jamais au-dela de la fin', () {
      const extract = Duration(seconds: 20);
      expect(BlindTestHost.extractStart(_t('a', 'X', seconds: 200), extract),
          const Duration(seconds: 60));
      expect(BlindTestHost.extractStart(_t('b', 'X', seconds: 600), extract),
          const Duration(seconds: 90));
      expect(BlindTestHost.extractStart(_t('c', 'X', seconds: 30), extract),
          const Duration(seconds: 5));
      expect(BlindTestHost.extractStart(_t('d', 'X', seconds: 20), extract),
          Duration.zero);
    });
  });

  test('deroule : DJ en pause, extrait, manche, revelation, fin', () async {
    expect(host.start(rounds: 2), isTrue);
    expect(djSuspended, [true]);
    expect(relay.sent, ['start 2']);

    await host.nextRound();
    expect(playback.played, hasLength(1));
    final round = relay.rounds.single;
    expect(
        round.choices[round.answer], BlindTestHost.label(host.current!.track));
    expect(round.song.title, host.current!.track.title);

    host.reveal();
    await host.nextRound();
    expect(host.hasNextRound, isFalse);
    host.stop();
    expect(djSuspended, [true, false]);
    expect(relay.sent, ['start 2', 'round', 'reveal', 'round', 'stop']);
    host.close();
    expect(relay.sent.last, 'close');
  });

  test('la revelation part toute seule a la fin du chrono', () async {
    host.start(rounds: 1, extract: const Duration(milliseconds: 20));
    await host.nextRound();
    await Future.delayed(const Duration(milliseconds: 60));
    expect(relay.sent.last, 'reveal');
  });

  test('DJ en pause : rien n est annonce aux invites', () {
    final party = _RecordingDjParty();
    final dj = PartyHostDj(party, _IdlePlayback())..suspended = true;
    dj.onTrackStarted(const PartySong(songId: 's1', title: 'Secret'));
    expect(party.announced, isEmpty);
    dj.suspended = false;
    dj.onTrackStarted(const PartySong(songId: 's2', title: 'Pas secret'));
    expect(party.announced, ['s2']);
  });

  group('contre le relais', () {
    late InMemoryPartyRelay hub;
    late DateTime now;
    final controllers = <PartyController>[];

    PartyController phone() {
      final c = PartyController(
        connect: hub.connect,
        retryDelays: const [Duration(milliseconds: 1)],
        now: () => now,
      );
      controllers.add(c);
      return c;
    }

    setUp(() {
      now = DateTime.now();
      hub = InMemoryPartyRelay(now: () => now);
    });

    tearDown(() {
      for (final c in controllers) {
        c.dispose();
      }
      controllers.clear();
    });

    Future<void> settle() => pumpEventQueue(times: 50);

    test('une partie : la reponse reste secrete, les points arrivent',
        () async {
      final h = phone();
      expect(
          await h.create(
            relayUrl: relayUrl,
            partyName: 'Anniv',
            hostName: 'Thibault',
            auth: goodHostAuth,
          ),
          isTrue);
      await settle();
      expect(h.supportsBlindTest, isTrue);
      final lea = phone();
      await lea.join(relayUrl: relayUrl, code: h.code!, name: 'Léa');
      final tom = phone();
      await tom.join(relayUrl: relayUrl, code: h.code!, name: 'Tom');
      await settle();

      final game = BlindTestHost(
        relay: h,
        playback: FakePlayback(),
        library: () => _library,
        setDjSuspended: (_) {},
        random: Random(2),
      );
      addTearDown(game.dispose);
      expect(game.start(rounds: 3), isTrue);
      await settle();
      expect(lea.blindTest!.phase, BlindTestPhase.ready);

      await game.nextRound();
      await settle();
      final question = lea.blindTest!;
      expect(question.phase, BlindTestPhase.question);
      expect(question.choices, hasLength(4));
      expect(question.answer, isNull);
      expect(h.blindTest!.answer, isNotNull);

      final good = h.blindTest!.answer!;
      lea.answerBlindTest(good);
      tom.answerBlindTest((good + 1) % 4);
      await settle();
      expect(h.blindTest!.answered, 2);

      game.reveal();
      await settle();
      expect(lea.blindTest!.phase, BlindTestPhase.reveal);
      expect(lea.blindTest!.answer, good);
      expect(lea.blindTest!.myGained, greaterThan(100));
      expect(tom.blindTest!.myGained, 0);
      expect(lea.blindTest!.scores.first.name, 'Léa');
      expect(lea.blindTest!.song!.title, game.current!.track.title);

      game.close();
      await settle();
      expect(lea.blindTest, isNull);
    });
  });
}

class _RecordingDjParty implements PartyDjParty {
  final announced = <String>[];
  @override
  bool get isHost => true;
  @override
  bool get isInParty => true;
  @override
  List<PartyQueueItem> get queueItems => const [];
  @override
  String? get nowPlayingSongId => null;
  @override
  Iterable<String> get playedSongIds => const [];
  @override
  void announceNowPlaying({String? itemId, PartySong? song, String? by}) =>
      announced.add(song?.songId ?? itemId ?? '');
}

class _IdlePlayback implements PartyPlayback {
  @override
  bool get isIdle => false;
  @override
  String? get currentSongId => null;
  @override
  bool get hasUpcoming => false;
  @override
  Future<void> play(PartySong song) async {}
  @override
  void setUpNext(PartySong? song) {}
}
