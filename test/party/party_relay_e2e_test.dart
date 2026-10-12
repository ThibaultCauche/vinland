// Soiree complete contre la vraie logique du relais (jam_relay/lib/party/,
// branchee en memoire, voir fakes/hub_party_socket.dart) : un hote et trois
// telephones invites, comme le critere de fin de la session 17.
import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/controllers/party_controller.dart';
import 'package:vinland/controllers/party_host_dj.dart';
import 'package:vinland/services/party/party_models.dart';
import 'package:vinland/services/party/party_socket.dart';

import '../fakes/hub_party_socket.dart';

const relayUrl = 'wss://nas.test/jam';

class MemorySeatStore implements PartySeatStore {
  PartySeat? seat;
  @override
  Future<PartySeat?> load() async => seat;
  @override
  Future<void> save(PartySeat? value) async => seat = value;
}

class RecordingPlayback implements PartyPlayback {
  @override
  bool isIdle = true;
  @override
  String? currentSongId;
  final played = <String>[];
  final upNext = <String?>[];

  @override
  Future<void> play(PartySong song) async {
    played.add(song.songId);
    currentSongId = song.songId;
    isIdle = false;
  }

  @override
  void setUpNext(PartySong? song) => upNext.add(song?.songId);
}

Future<void> settle() => pumpEventQueue(times: 50);

void main() {
  late InMemoryPartyRelay relay;
  late DateTime now;
  final controllers = <PartyController>[];

  PartyController phone({PartySeatStore? store}) {
    final c = PartyController(
      connect: relay.connect,
      store: store,
      retryDelays: const [Duration(milliseconds: 1)],
      now: () => now,
    );
    controllers.add(c);
    return c;
  }

  Future<PartyController> host({PartyRules rules = const PartyRules()}) async {
    final h = phone();
    final ok = await h.create(
      relayUrl: relayUrl,
      partyName: 'Anniv',
      hostName: 'Thibault',
      auth: goodHostAuth,
      rules: rules,
    );
    expect(ok, isTrue, reason: h.error);
    await settle();
    return h;
  }

  Future<PartyController> guest(String name, String code,
      {PartySeatStore? store}) async {
    final g = phone(store: store);
    final ok = await g.join(relayUrl: relayUrl, code: code, name: name);
    expect(ok, isTrue, reason: g.error);
    await settle();
    return g;
  }

  List<String> titles(PartyController c) =>
      [for (final i in c.queue.items) i.song.title];

  setUp(() {
    now = DateTime.now();
    relay = InMemoryPartyRelay(now: () => now);
  });

  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  });

  test('3 invites proposent, votent ; veto et lecture chez l hote', () async {
    final h = await host();
    final playback = RecordingPlayback();
    final dj = PartyHostDj(h, playback);
    h.addListener(dj.sync);
    expect(h.code, matches(RegExp(r'^[A-HJKMNP-Z2-9]{6}$')));

    final lea = await guest('Léa', h.code!);
    final tom = await guest('Tom', h.code!);
    final zoe = await guest('Zoé', h.code!);
    expect(h.queue.guestCount, 3);
    expect(
        h.queue.members.map((m) => m.name), containsAll(['Léa', 'Tom', 'Zoé']));

    // Recherche dans le catalogue du relais.
    lea.search('titre 1');
    await settle();
    expect(lea.searchResults.map((s) => s.songId), contains('s1'));

    // Lea propose 2 titres, Tom 1 : chacun son tour.
    lea.suggest(lea.searchResults.firstWhere((s) => s.songId == 's1'));
    await settle();
    // Le lecteur de l'hote etait a l'arret : la 1re proposition part.
    expect(playback.played, ['s1']);
    dj.onTrackStarted(const PartySong(songId: 's1', title: 'Titre 1'));
    await settle();
    expect(zoe.nowPlaying?.title, 'Titre 1');
    expect(titles(zoe), isEmpty);

    now = now.add(const Duration(seconds: 20));
    lea.suggest(const PartySong(songId: 's2', title: 'Titre 2'));
    lea.suggest(const PartySong(songId: 's3', title: 'Titre 3'));
    await settle();
    tom.suggest(const PartySong(songId: 's4', title: 'Titre 4'));
    await settle();
    expect(titles(zoe), ['Titre 2', 'Titre 4', 'Titre 3']);
    expect(playback.upNext.last, 's2');

    // Zoe vote pour le titre de Tom : il passe devant dans son tour.
    final tomItem = zoe.queue.items.firstWhere((i) => i.song.songId == 's4');
    zoe.vote(tomItem.id, 1);
    await settle();
    expect(titles(lea), ['Titre 4', 'Titre 2', 'Titre 3']);
    expect(zoe.queue.items.first.myVote, 1);
    expect(tom.queue.items.first.mine, isTrue);
    expect(playback.upNext.last, 's4');

    // Veto de l'hote sur le titre 2.
    final item2 = h.queue.items.firstWhere((i) => i.song.songId == 's2');
    h.veto(item2.id);
    await settle();
    expect(titles(tom), ['Titre 4', 'Titre 3']);

    // Le titre de Tom demarre chez l'hote : il quitte la file partout.
    playback.currentSongId = 's4';
    dj.onTrackStarted(const PartySong(songId: 's4', title: 'Titre 4'));
    await settle();
    expect(lea.nowPlaying?.title, 'Titre 4');
    expect(titles(lea), ['Titre 3']);
    expect(playback.upNext.last, 's3');
  });

  test('un doublon est refuse avec un message clair', () async {
    final h = await host();
    final lea = await guest('Léa', h.code!);
    final tom = await guest('Tom', h.code!);
    final notices = <String>[];
    tom.notices.listen(notices.add);
    lea.suggest(const PartySong(songId: 's5', title: 'Titre 5'));
    await settle();
    tom.suggest(const PartySong(songId: 's5', title: 'Titre 5'));
    await settle();
    expect(notices, contains(partyErrorMessage('duplicate')));
    expect(titles(h), ['Titre 5']);
  });

  test("votes coupes par l'hote : l'invite ne peut pas voter", () async {
    final h = await host(rules: const PartyRules(votesEnabled: false));
    final lea = await guest('Léa', h.code!);
    final tom = await guest('Tom', h.code!);
    expect(tom.rules.votesEnabled, isFalse);
    lea.suggest(const PartySong(songId: 's1', title: 'Titre 1'));
    await settle();
    tom.vote(tom.queue.items.single.id, 1);
    await settle();
    expect(lea.queue.items.single.score, 0);
  });

  test('un invite exclu voit pourquoi et ses titres disparaissent', () async {
    final h = await host();
    final lea = await guest('Léa', h.code!);
    lea.suggest(const PartySong(songId: 's1', title: 'Titre 1'));
    await settle();
    h.kick(lea.memberId!, ban: true);
    await settle();
    expect(lea.phase, PartyPhase.ended);
    expect(lea.endReason, PartyEndReason.banned);
    expect(titles(h), isEmpty);
  });

  test("changer le code : l'ancien ne marche plus", () async {
    final h = await host();
    final old = h.code!;
    h.rotateCode();
    await settle();
    expect(h.code, isNot(old));
    final late = phone();
    expect(
        await late.join(relayUrl: relayUrl, code: old, name: 'Max'), isFalse);
    expect(late.error, partyErrorMessage('bad_code'));
    expect(late.phase, PartyPhase.idle);
  });

  test('coupure reseau : on revient tout seul avec le jeton', () async {
    final h = await host();
    final lea = await guest('Léa', h.code!);
    lea.suggest(const PartySong(songId: 's1', title: 'Titre 1'));
    await settle();
    relay.dropAll();
    await settle();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await settle();
    expect(lea.phase, PartyPhase.inParty);
    expect(h.phase, PartyPhase.inParty);
    expect(titles(lea), ['Titre 1']);
    expect(lea.queue.items.single.mine, isTrue);
  });

  test("l'app redemarre : la place gardee permet de revenir", () async {
    final h = await host();
    final store = MemorySeatStore();
    final lea = await guest('Léa', h.code!, store: store);
    final memberId = lea.memberId;
    expect(store.seat?.partyName, 'Anniv');

    final again = phone(store: store);
    expect(await again.resume(), isTrue);
    await settle();
    expect(again.memberId, memberId);
    expect(again.role, PartyRole.guest);
  });

  test("fin de soiree par l'hote : tous les invites sont prevenus", () async {
    final h = await host();
    final store = MemorySeatStore();
    final lea = await guest('Léa', h.code!, store: store);
    await h.end();
    await settle();
    expect(lea.phase, PartyPhase.ended);
    expect(lea.endReason, PartyEndReason.host);
    expect(store.seat, isNull, reason: 'plus rien a reprendre');
  });

  test('sans compte Navidrome valide, pas de soiree', () async {
    final pirate = phone();
    final ok = await pirate.create(
      relayUrl: relayUrl,
      partyName: 'Pirate',
      hostName: 'X',
      auth: const {'u': 'thibault', 't': 'faux', 's': 'sel'},
    );
    expect(ok, isFalse);
    expect(pirate.error, partyErrorMessage('unauthorized'));
  });

  test('relais injoignable : message clair, pas de blocage', () async {
    relay.reachable = false;
    final lea = phone();
    expect(await lea.join(relayUrl: relayUrl, code: 'K7QX2M', name: 'Léa'),
        isFalse);
    expect(lea.error, contains('injoignable'));
    expect(lea.phase, PartyPhase.idle);
  });
}
