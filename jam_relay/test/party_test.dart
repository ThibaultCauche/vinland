// Regles du mode Soiree (docs/soiree-protocole.md), sans reseau : de
// fausses connexions, une horloge qu'on avance a la main et un faux
// catalogue Navidrome.
import 'dart:typed_data';

import 'package:jam_relay/party/catalog.dart';
import 'package:jam_relay/party/party.dart';
import 'package:jam_relay/party/party_hub.dart';
import 'package:jam_relay/party/party_token.dart';
import 'package:test/test.dart';

class FakeConn implements PartyConnection {
  final messages = <Map<String, dynamic>>[];
  bool closed = false;

  @override
  void send(Map<String, dynamic> message) => messages.add(message);

  @override
  void close() => closed = true;

  Map<String, dynamic> last(String type) =>
      messages.lastWhere((m) => m['type'] == type,
          orElse: () => throw StateError('pas de "$type" dans $messages'));

  List<Map<String, dynamic>> all(String type) =>
      messages.where((m) => m['type'] == type).toList();

  String? get lastErrorCode {
    final errors = all('party_error');
    return errors.isEmpty ? null : errors.last['code'] as String;
  }

  List<String> get queueTitles => [
        for (final item in last('queue_state')['items'] as List)
          item['title'] as String
      ];
}

class FakeCatalog implements PartyCatalog {
  final songs = <String, PartySong>{
    for (var i = 1; i <= 20; i++)
      's$i': PartySong(songId: 's$i', title: 'Titre $i', artist: 'Artiste'),
  };
  String goodToken = 'bon-jeton';

  @override
  Future<List<PartySong>> search(String query, {int limit = 20}) async =>
      songs.values.where((s) => s.title.contains(query)).take(limit).toList();

  @override
  Future<PartySong?> song(String songId) async => songs[songId];

  @override
  Future<CoverImage?> cover(String coverId, int size) async =>
      CoverImage(Uint8List.fromList([size]), 'image/jpeg');

  @override
  Future<bool> verifyHost(HostAuth auth) async => auth.token == goodToken;
}

void main() {
  late DateTime now;
  late FakeCatalog catalog;
  late PartyHub hub;
  late FakeConn host;
  late String code;

  const hostAuth = {'u': 'thibault', 't': 'bon-jeton', 's': 'sel'};

  Future<FakeConn> join(String name, {String? withCode}) async {
    final conn = FakeConn();
    await hub.handle(conn, {
      'type': 'party_join',
      'v': 1,
      'code': withCode ?? code,
      'name': name,
    });
    return conn;
  }

  Future<void> suggest(FakeConn conn, String songId) =>
      hub.handle(conn, {'type': 'suggest', 'songId': songId});

  setUp(() async {
    now = DateTime.utc(2026, 10, 12, 20);
    catalog = FakeCatalog();
    hub = PartyHub(
      signer: PartyTokenSigner(List.filled(32, 7)),
      catalog: catalog,
      now: () => now,
    );
    host = FakeConn();
    await hub.handle(host, {
      'type': 'party_create',
      'v': 1,
      'name': 'Anniv',
      'hostName': 'Thibault',
      'auth': hostAuth,
    });
    code = host.last('party_joined')['code'] as String;
  });

  group('creation', () {
    test("l'hote recoit un code court lisible et un jeton", () {
      final joined = host.last('party_joined');
      expect(joined['role'], 'host');
      expect(code, matches(RegExp(r'^[A-HJKMNP-Z2-9]{6}$')));
      expect(joined['token'], isA<String>());
    });

    test('sans identifiants Navidrome valides, pas de soiree', () async {
      final intruder = FakeConn();
      await hub.handle(intruder, {
        'type': 'party_create',
        'hostName': 'Pirate',
        'auth': {'u': 'thibault', 't': 'faux', 's': 'sel'},
      });
      expect(intruder.lastErrorCode, 'unauthorized');
      final noAuth = FakeConn();
      await hub.handle(noAuth, {'type': 'party_create', 'hostName': 'X'});
      expect(noAuth.lastErrorCode, 'unauthorized');
      expect(hub.partyCount, 1);
    });

    test('un client plus recent que le relais est prevenu', () async {
      final conn = FakeConn();
      await hub.handle(
          conn, {'type': 'party_join', 'v': 2, 'code': code, 'name': 'Futur'});
      expect(conn.lastErrorCode, 'version');
    });

    test('pas plus de 3 soirees ouvertes par compte', () async {
      for (var i = 0; i < 2; i++) {
        await hub.handle(FakeConn(), {
          'type': 'party_create',
          'hostName': 'Thibault',
          'auth': hostAuth,
        });
      }
      final fourth = FakeConn();
      await hub.handle(fourth,
          {'type': 'party_create', 'hostName': 'Thibault', 'auth': hostAuth});
      expect(fourth.lastErrorCode, 'full');
    });
  });

  group('rejoindre', () {
    test('un code faux est refuse', () async {
      final guest = await join('Lea', withCode: 'ZZZZZZ');
      expect(guest.lastErrorCode, 'bad_code');
      expect(guest.all('party_joined'), isEmpty);
    });

    test('cinq codes faux de suite ferment la connexion', () async {
      final guest = FakeConn();
      for (var i = 0; i < 5; i++) {
        await hub.handle(
            guest, {'type': 'party_join', 'code': 'ZZZZZ$i', 'name': 'Bot'});
      }
      expect(guest.closed, isTrue);
    });

    test('trop de codes faux sur tout le relais bloquent les essais', () async {
      for (var i = 0; i < 60; i++) {
        await join('Bot', withCode: 'ZZZZZZ');
      }
      final honest = await join('Lea');
      expect(honest.lastErrorCode, 'rate_limited');
      now = now.add(const Duration(seconds: 5));
      final later = await join('Lea');
      expect(later.last('party_joined')['role'], 'guest');
    });

    test('le code se tape aussi en minuscules', () async {
      final guest = await join('Lea', withCode: code.toLowerCase());
      expect(guest.last('party_joined')['role'], 'guest');
      expect(guest.last('party_joined').containsKey('code'), isFalse,
          reason: "seul l'hote recoit le code a partager");
    });

    test('un invite revient avec son jeton apres une coupure', () async {
      final guest = await join('Lea');
      await suggest(guest, 's1');
      final token = guest.last('party_joined')['token'];
      hub.disconnected(guest);

      final back = FakeConn();
      await hub.handle(back, {'type': 'party_join', 'token': token});
      expect(back.last('party_joined')['memberId'],
          guest.last('party_joined')['memberId']);
      expect((back.last('queue_state')['items'] as List).single['mine'], true);
    });

    test("les invites voient quand l'hote est hors ligne", () async {
      final guest = await join('Lea');
      expect(guest.last('queue_state')['hostOnline'], isTrue);
      hub.disconnected(host);
      expect(guest.last('queue_state')['hostOnline'], isFalse);
    });

    test('un jeton trafique est refuse', () async {
      final guest = await join('Lea');
      final token = guest.last('party_joined')['token'] as String;
      final forged = FakeConn();
      await hub.handle(forged, {
        'type': 'party_join',
        'token': '${token.substring(0, token.length - 2)}AA',
      });
      expect(forged.lastErrorCode, 'bad_token');
    });
  });

  group('propositions', () {
    test("une proposition arrive dans la file de l'hote", () async {
      final guest = await join('Lea');
      await suggest(guest, 's1');
      expect(guest.last('suggested')['songId'], 's1');
      final item = (host.last('queue_state')['items'] as List).single;
      expect(item['title'], 'Titre 1');
      expect(item['by'], 'Lea');
    });

    test('les infos du titre viennent de Navidrome, pas de l\'invite',
        () async {
      final guest = await join('Lea');
      await hub.handle(
          guest, {'type': 'suggest', 'songId': 's1', 'title': 'Faux titre'});
      expect(host.queueTitles, ['Titre 1']);
    });

    test('un titre inconnu de Navidrome est refuse', () async {
      final guest = await join('Lea');
      await suggest(guest, 'n-existe-pas');
      expect(guest.lastErrorCode, 'not_found');
    });

    test('un titre deja dans la file, en cours ou recent est refuse', () async {
      final lea = await join('Lea');
      final tom = await join('Tom');
      await suggest(lea, 's1');
      await suggest(tom, 's1');
      expect(tom.lastErrorCode, 'duplicate');

      final itemId = lea.last('suggested')['itemId'];
      await hub.handle(host, {'type': 'now_playing', 'itemId': itemId});
      now = now.add(const Duration(seconds: 30));
      await suggest(tom, 's1');
      expect(tom.lastErrorCode, 'duplicate', reason: 'en cours');

      await hub.handle(
          host, {'type': 'now_playing', 'songId': 's9', 'title': 'Titre 9'});
      now = now.add(const Duration(seconds: 30));
      await suggest(tom, 's1');
      expect(tom.lastErrorCode, 'duplicate', reason: 'joue il y a peu');
    });

    test('pas plus de 3 titres en attente par invite', () async {
      final guest = await join('Lea');
      for (final id in ['s1', 's2', 's3']) {
        await suggest(guest, id);
        now = now.add(const Duration(seconds: 10));
      }
      await suggest(guest, 's4');
      expect(guest.lastErrorCode, 'limit');
      // L'hote, lui, n'a pas de limite.
      for (final id in ['s5', 's6', 's7', 's8']) {
        await suggest(host, id);
      }
      expect(host.lastErrorCode, isNull);
    });

    test('proposer trop vite est freine', () async {
      final guest = await join('Lea');
      await hub.handle(host, {'type': 'party_end'});
      final party2 = FakeConn();
      await hub.handle(party2, {
        'type': 'party_create',
        'hostName': 'Thibault',
        'auth': hostAuth,
        'rules': {'maxPendingPerGuest': 10},
      });
      code = party2.last('party_joined')['code'] as String;
      final fast = await join('Rapide');
      for (final id in ['s1', 's2', 's3', 's4']) {
        await suggest(fast, id);
      }
      expect(fast.lastErrorCode, 'rate_limited');
      expect(guest.all('party_ended'), isNotEmpty);
    });

    test('la file alterne entre les invites', () async {
      final lea = await join('Lea');
      final tom = await join('Tom');
      for (final id in ['s1', 's2', 's3']) {
        await suggest(lea, id);
        now = now.add(const Duration(seconds: 10));
      }
      await suggest(tom, 's4');
      expect(host.queueTitles, ['Titre 1', 'Titre 4', 'Titre 2', 'Titre 3']);
    });

    test('les votes departagent un meme tour', () async {
      final lea = await join('Lea');
      final tom = await join('Tom');
      final zoe = await join('Zoe');
      await suggest(lea, 's1');
      await suggest(tom, 's2');
      final tomItem = tom.last('suggested')['itemId'];
      await hub.handle(zoe, {'type': 'vote', 'itemId': tomItem, 'value': 1});
      expect(host.queueTitles, ['Titre 2', 'Titre 1']);
      final item = (zoe.last('queue_state')['items'] as List).first;
      expect(item['myVote'], 1);
      expect(item['score'], 1);

      await hub.handle(zoe, {'type': 'vote', 'itemId': tomItem, 'value': 0});
      expect(host.queueTitles, ['Titre 1', 'Titre 2']);
    });

    test('un vote hors de -1..1 est refuse', () async {
      final lea = await join('Lea');
      await suggest(lea, 's1');
      await hub.handle(lea, {
        'type': 'vote',
        'itemId': lea.last('suggested')['itemId'],
        'value': 50,
      });
      expect(lea.lastErrorCode, 'invalid');
    });
  });

  group("pouvoirs de l'hote", () {
    test('un invite ne peut pas faire de veto ni exclure', () async {
      final lea = await join('Lea');
      await suggest(lea, 's1');
      await hub.handle(
          lea, {'type': 'veto', 'itemId': lea.last('suggested')['itemId']});
      expect(lea.lastErrorCode, 'forbidden');
      await hub.handle(lea, {'type': 'party_end'});
      expect(lea.lastErrorCode, 'forbidden');
      expect(hub.partyCount, 1);
    });

    test("le veto de l'hote retire le titre", () async {
      final lea = await join('Lea');
      await suggest(lea, 's1');
      await hub.handle(
          host, {'type': 'veto', 'itemId': lea.last('suggested')['itemId']});
      expect(host.queueTitles, isEmpty);
    });

    test('un invite banni perd ses titres et ne peut plus revenir', () async {
      final lea = await join('Lea');
      await suggest(lea, 's1');
      final token = lea.last('party_joined')['token'];
      final memberId = lea.last('party_joined')['memberId'];
      expect(
          (host.last('queue_state')['members'] as List).single['name'], 'Lea');

      await hub
          .handle(host, {'type': 'kick', 'memberId': memberId, 'ban': true});
      expect(lea.last('kicked')['banned'], isTrue);
      expect(lea.closed, isTrue);
      expect(host.queueTitles, isEmpty);
      expect(host.last('queue_state')['members'], isEmpty);

      final back = FakeConn();
      await hub.handle(back, {'type': 'party_join', 'token': token});
      expect(back.lastErrorCode, 'banned');
    });

    test("changer le code empeche d'entrer avec l'ancien", () async {
      await hub.handle(host, {'type': 'party_rotate_code'});
      final newCode = host.last('party_code')['code'];
      expect(newCode, isNot(code));
      expect((await join('Lea')).lastErrorCode, 'bad_code');
      expect((await join('Lea', withCode: newCode)).last('party_joined'),
          isNotNull);
    });

    test("now_playing previent tout le monde et vide l'element de la file",
        () async {
      final lea = await join('Lea');
      await suggest(lea, 's1');
      await hub.handle(host,
          {'type': 'now_playing', 'itemId': lea.last('suggested')['itemId']});
      expect(lea.last('now_playing')['song']['songId'], 's1');
      expect(lea.queueTitles, isEmpty);
    });
  });

  group('recherche et pochettes', () {
    test('un invite cherche dans le catalogue sans compte', () async {
      final lea = await join('Lea');
      await hub
          .handle(lea, {'type': 'search', 'requestId': 4, 'query': 'Titre 1'});
      final results = lea.last('search_results');
      expect(results['requestId'], 4);
      expect(
          (results['songs'] as List).first.keys,
          unorderedEquals(
              ['id', 'title', 'artist', 'album', 'durationMs', 'coverId']));
    });

    test('chercher trop vite est freine', () async {
      final lea = await join('Lea');
      for (var i = 0; i < 6; i++) {
        await hub
            .handle(lea, {'type': 'search', 'requestId': i, 'query': 'Titre'});
      }
      expect(lea.lastErrorCode, 'rate_limited');
      expect(lea.last('party_error')['requestId'], 5);
    });

    test("sans soiree, pas de recherche", () async {
      final stranger = FakeConn();
      await hub.handle(
          stranger, {'type': 'search', 'requestId': 1, 'query': 'Titre'});
      expect(stranger.lastErrorCode, 'not_in_party');
    });

    test('les pochettes exigent un jeton et sont redimensionnees', () async {
      final lea = await join('Lea');
      final token = lea.last('party_joined')['token'] as String;
      expect((await hub.cover(null, 'al-1', 300)).$1, 401);
      expect((await hub.cover('faux', 'al-1', 300)).$1, 401);
      final (status, image) = await hub.cover(token, 'al-1', 5000);
      expect(status, 200);
      expect(image!.bytes.single, 600 % 256, reason: 'taille bornee a 600');
      expect((await hub.cover(token, '../rest/getUser', 300)).$1, 400);
    });
  });

  group('expiration', () {
    test('la soiree se termine apres 6 h et les jetons ne passent plus',
        () async {
      final lea = await join('Lea');
      final token = lea.last('party_joined')['token'];
      now = now.add(const Duration(hours: 6));
      hub.sweep();
      expect(lea.last('party_ended')['reason'], 'expired');
      expect(lea.closed, isTrue);
      expect(hub.partyCount, 0);

      final back = FakeConn();
      await hub.handle(back, {'type': 'party_join', 'token': token});
      expect(back.lastErrorCode, 'bad_token');
    });

    test("un jeton d'une soiree terminee par l'hote dit pourquoi", () async {
      final lea = await join('Lea');
      final token = lea.last('party_joined')['token'];
      await hub.handle(host, {'type': 'party_end'});
      expect(lea.last('party_ended')['reason'], 'host');
      final back = FakeConn();
      await hub.handle(back, {'type': 'party_join', 'token': token});
      expect(back.lastErrorCode, 'expired');
    });
  });

  test('un message de soiree trop long est refuse', () async {
    final lea = await join('Lea');
    await hub.handle(lea, {'type': 'suggest', 'songId': 's1'}, rawLength: 9000);
    expect(lea.lastErrorCode, 'invalid');
  });

  group('jetons', () {
    final signer = PartyTokenSigner(List.filled(32, 1));
    final claims = PartyClaims(
      partyId: 'p1',
      memberId: 'm2',
      role: 'guest',
      expiresAtMs: DateTime.utc(2026, 10, 13).millisecondsSinceEpoch,
    );

    test('un jeton signe se relit tel quel avant expiration', () {
      final read =
          signer.verify(signer.sign(claims), DateTime.utc(2026, 10, 12));
      expect(read!.memberId, 'm2');
      expect(read.isHost, isFalse);
    });

    test("un jeton d'un autre relais (autre cle) est refuse", () {
      final other = PartyTokenSigner(List.filled(32, 2));
      expect(other.verify(signer.sign(claims), DateTime.utc(2026, 10, 12)),
          isNull);
    });

    test('un jeton expire ou mal forme est refuse', () {
      expect(signer.verify(signer.sign(claims), DateTime.utc(2026, 10, 13)),
          isNull);
      expect(signer.verify('pas-un-jeton', DateTime.utc(2026)), isNull);
      expect(signer.verify('a.b.c', DateTime.utc(2026)), isNull);
    });
  });
}
