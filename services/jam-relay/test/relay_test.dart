// Regles du relais (protocole v2) testees en memoire : le relais tourne dans
// le meme processus que le test, sur un port libre, et on lui parle en
// WebSocket comme le fait l'app. Le chemin nominal complet via le vrai
// binaire reste couvert par relay_smoke_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jam_relay/relay.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Client de test : garde tous les messages recus pour pouvoir attendre
/// celui qui nous interesse, meme s'il est arrive avant qu'on l'attende.
class _Client {
  final WebSocketChannel _channel;
  final _messages = <Map<String, dynamic>>[];
  final _arrivals = StreamController<void>.broadcast();
  final closed = Completer<void>();

  _Client(this._channel) {
    _channel.stream.listen((raw) {
      _messages.add(jsonDecode(raw as String) as Map<String, dynamic>);
      _arrivals.add(null);
    }, onDone: () {
      if (!closed.isCompleted) closed.complete();
      _arrivals.add(null);
    });
  }

  static Future<_Client> connect(int port) async {
    final channel =
        WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port/jam'));
    await channel.ready;
    return _Client(channel);
  }

  void send(Map<String, dynamic> message) =>
      _channel.sink.add(jsonEncode(message));

  void sendRaw(String raw) => _channel.sink.add(raw);

  Future<Map<String, dynamic>> next(String type) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      final index = _messages.indexWhere((m) => m['type'] == type);
      if (index != -1) return _messages.removeAt(index);
      final left = deadline.difference(DateTime.now());
      if (left.isNegative) {
        throw TimeoutException('pas de message "$type" (recus : $_messages)');
      }
      await _arrivals.stream.first.timeout(left, onTimeout: () {});
    }
  }

  /// Verifie qu'aucun message de ce type n'arrive dans le delai donne.
  Future<void> expectNone(String type,
      {Duration within = const Duration(milliseconds: 300)}) async {
    await Future<void>.delayed(within);
    expect(_messages.where((m) => m['type'] == type), isEmpty,
        reason: 'message "$type" inattendu');
  }

  Future<void> close() => _channel.sink.close();
}

void main() {
  late HttpServer server;
  late JamRelay relay;
  late int port;

  Future<void> start([RelayLimits limits = const RelayLimits()]) async {
    relay = JamRelay(limits: limits, log: (_) {});
    server = await shelf_io.serve(relay.handler, '127.0.0.1', 0);
    port = server.port;
  }

  tearDown(() => server.close(force: true));

  /// Cree une session et renvoie l'hote et le hostSecret recu.
  Future<(_Client, String)> host(String id, {String? hostSecret}) async {
    final c = await _Client.connect(port);
    c.send({
      'type': 'host',
      'sessionId': id,
      'username': 'hote',
      if (hostSecret != null) 'hostSecret': hostSecret,
    });
    final joined = await c.next('joined');
    expect(joined['role'], 'host');
    return (c, joined['hostSecret'] as String);
  }

  Future<_Client> join(String id, String username) async {
    final c = await _Client.connect(port);
    c.send({'type': 'join', 'sessionId': id, 'username': username});
    expect(await c.next('joined'), containsPair('role', 'participant'));
    return c;
  }

  group('hebergement', () {
    setUp(() => start());

    test("la creation d'une session remet un hostSecret aleatoire a l'hote",
        () async {
      final (_, secretA) = await host('session-aaaa');
      final (_, secretB) = await host('session-bbbb');
      expect(secretA.length, greaterThanOrEqualTo(40));
      expect(secretA, isNot(secretB));
    });

    test(
        "un ami qui connait le code de la session ne peut pas en detourner "
        "l'hebergement (scenario de l'audit)", () async {
      final (hote, _) = await host('soiree-1234');
      final pirate = await _Client.connect(port);
      pirate.send(
          {'type': 'host', 'sessionId': 'soiree-1234', 'username': 'pirate'});
      expect(await pirate.next('error'),
          containsPair('message', 'hebergement refuse'));

      // Avec un faux secret, meme refus.
      pirate.send({
        'type': 'host',
        'sessionId': 'soiree-1234',
        'username': 'pirate',
        'hostSecret': 'x' * 43,
      });
      expect(await pirate.next('error'),
          containsPair('message', 'hebergement refuse'));

      // L'hote garde la main : il n'a pas ete retrograde, et ses etats
      // continuent d'arriver aux participants.
      await hote.expectNone('host_transferred');
      final ami = await join('soiree-1234', 'ami');
      hote.send({'type': 'state', 'trackId': 't1', 'isPlaying': true});
      expect(await ami.next('state'), containsPair('trackId', 't1'));
    });

    test("un participant ne peut pas diffuser d'etat a la place de l'hote",
        () async {
      final (_, _) = await host('soiree-1234');
      final ami = await join('soiree-1234', 'ami');
      final autre = await join('soiree-1234', 'autre');
      ami.send({'type': 'state', 'trackId': 'faux', 'isPlaying': true});
      await autre.expectNone('state');
    });

    test(
        'un autre appareil du meme compte reprend la main avec le secret '
        'partage (synchro perso)', () async {
      final secret = 'c' * 64;
      final (pc, _) = await host('perso-0123456789abcdef', hostSecret: secret);
      final (telephone, recu) =
          await host('perso-0123456789abcdef', hostSecret: secret);
      expect(recu, secret);
      expect(await pc.next('host_transferred'),
          containsPair('role', 'participant'));
      telephone.send({'type': 'state', 'trackId': 't2', 'isPlaying': true});
      expect(await pc.next('state'), containsPair('trackId', 't2'));
    });

    test('un hostSecret fourni trop court est remplace par un secret du relais',
        () async {
      final (_, recu) = await host('session-cccc', hostSecret: 'court');
      expect(recu, isNot('court'));
    });

    test('un sessionId invalide est refuse', () async {
      final c = await _Client.connect(port);
      c.send({'type': 'host', 'sessionId': 'abc', 'username': 'x'});
      expect(
          await c.next('error'), containsPair('message', 'sessionId invalide'));
      c.send({'type': 'host', 'sessionId': 'a b/../c-def', 'username': 'x'});
      expect(
          await c.next('error'), containsPair('message', 'sessionId invalide'));
    });

    test('chaque message du relais porte la version du protocole', () async {
      final c = await _Client.connect(port);
      c.send({'type': 'host', 'sessionId': 'session-vvvv'});
      expect(await c.next('joined'), containsPair('v', 2));
    });
  });

  group('rejoindre, commandes et transfert', () {
    setUp(() => start());

    test("les commandes d'un participant ne vont qu'a l'hote", () async {
      final (hote, _) = await host('soiree-1234');
      final ami = await join('soiree-1234', 'ami');
      final autre = await join('soiree-1234', 'autre');
      ami.send({'type': 'command', 'action': 'next'});
      expect(await hote.next('command'), containsPair('action', 'next'));
      await autre.expectNone('command');
    });

    test(
        "le transfert d'hebergement remet un nouveau secret au nouvel hote, "
        "et l'ancien ne peut plus reprendre la main avec l'ancien secret",
        () async {
      final (hote, ancienSecret) = await host('soiree-1234');
      final ami = await join('soiree-1234', 'ami');
      hote.send({'type': 'transfer_host', 'targetUsername': 'ami'});
      final promu = await ami.next('host_transferred');
      expect(promu['role'], 'host');
      expect(promu['hostSecret'], isA<String>());
      expect(promu['hostSecret'], isNot(ancienSecret));
      expect(await hote.next('host_transferred'),
          containsPair('role', 'participant'));

      // L'ancien hote ouvre une nouvelle connexion avec son ancien secret.
      final retour = await _Client.connect(port);
      retour.send({
        'type': 'host',
        'sessionId': 'soiree-1234',
        'hostSecret': ancienSecret,
      });
      expect(await retour.next('error'),
          containsPair('message', 'hebergement refuse'));
    });

    test('transferer a un pseudo absent renvoie une erreur', () async {
      final (hote, _) = await host('soiree-1234');
      hote.send({'type': 'transfer_host', 'targetUsername': 'personne'});
      expect(await hote.next('error'),
          containsPair('message', 'participant introuvable'));
    });

    test("le depart de l'hote ferme la session pour tout le monde", () async {
      final (hote, _) = await host('soiree-1234');
      final ami = await join('soiree-1234', 'ami');
      await hote.close();
      await ami.next('host_left');
      expect(relay.sessionCount, 0);
      final tardif = await _Client.connect(port);
      tardif.send({'type': 'join', 'sessionId': 'soiree-1234'});
      expect(await tardif.next('error'),
          containsPair('message', 'session introuvable'));
    });
  });

  group('limites', () {
    test('un message trop gros est refuse et la connexion fermee', () async {
      await start(const RelayLimits(maxMessageBytes: 1024));
      final (hote, _) = await host('soiree-1234');
      hote.sendRaw(jsonEncode({'type': 'state', 'pad': 'x' * 2000}));
      expect(await hote.next('error'),
          containsPair('message', 'message trop gros'));
      await hote.closed.future.timeout(const Duration(seconds: 5));
    });

    test('au-dela du nombre max de sessions, la creation est refusee',
        () async {
      await start(const RelayLimits(maxSessions: 2));
      await host('session-0001');
      await host('session-0002');
      final c = await _Client.connect(port);
      c.send({'type': 'host', 'sessionId': 'session-0003'});
      expect(await c.next('error'), containsPair('message', 'relais plein'));
    });

    test('au-dela du nombre max de participants, la session est pleine',
        () async {
      await start(const RelayLimits(maxPeersPerSession: 2));
      await host('soiree-1234');
      await join('soiree-1234', 'a');
      await join('soiree-1234', 'b');
      final c = await _Client.connect(port);
      c.send({'type': 'join', 'sessionId': 'soiree-1234', 'username': 'c'});
      expect(await c.next('error'), containsPair('message', 'session pleine'));
    });

    test("une connexion qui ne rejoint aucune session est fermee", () async {
      await start(const RelayLimits(handshakeTimeout: Duration(seconds: 1)));
      final c = await _Client.connect(port);
      await c.closed.future.timeout(const Duration(seconds: 5));
    });

    test('au-dela du nombre max de connexions, les suivantes sont refusees',
        () async {
      await start(const RelayLimits(maxConnections: 1));
      await host('soiree-1234');
      final c = await _Client.connect(port);
      expect(await c.next('error'), containsPair('message', 'relais plein'));
    });
  });
}
