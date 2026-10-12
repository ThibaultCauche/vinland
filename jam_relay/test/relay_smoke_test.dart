// Test de fumee du relais : on lance le vrai bin/server.dart dans un
// processus a part (sur un port libre choisi par l'OS) et on lui parle en
// WebSocket comme le ferait l'app. Il ne verifie que le chemin nominal
// (un hote cree la session, un ami la rejoint) : les regles de securite du
// Jam auront leurs propres tests avec la session 05.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Client de test : garde tous les messages recus pour pouvoir attendre
/// celui qui nous interesse, meme s'il est arrive avant qu'on l'attende.
class _Client {
  final WebSocketChannel _channel;
  final _messages = <Map<String, dynamic>>[];
  final _arrivals = StreamController<void>.broadcast();

  _Client(this._channel) {
    _channel.stream.listen((raw) {
      _messages.add(jsonDecode(raw as String) as Map<String, dynamic>);
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

  Future<void> close() => _channel.sink.close();
}

void main() {
  late Process server;
  late int port;

  setUp(() async {
    server = await Process.start(
      Platform.resolvedExecutable,
      ['run', 'bin/server.dart'],
      environment: {'PORT': '0'},
    );
    // Le serveur annonce son port sur stderr ("en ecoute sur :12345").
    final ready = Completer<int>();
    server.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final match = RegExp(r'en ecoute sur :(\d+)').firstMatch(line);
      if (match != null && !ready.isCompleted) {
        ready.complete(int.parse(match.group(1)!));
      }
    });
    port = await ready.future.timeout(const Duration(seconds: 60));
  });

  tearDown(() {
    server.kill();
  });

  test("un ami qui rejoint la session de l'hote est annonce a l'hote",
      () async {
    final host = await _Client.connect(port);
    host.send({'type': 'host', 'sessionId': 'soiree-test', 'username': 'hote'});
    expect(await host.next('joined'), containsPair('role', 'host'));

    final friend = await _Client.connect(port);
    friend
        .send({'type': 'join', 'sessionId': 'soiree-test', 'username': 'ami'});
    expect(await friend.next('joined'), containsPair('role', 'participant'));

    // L'hote recoit un premier participant_count a 0 en creant la session,
    // puis un a 1 quand l'ami arrive.
    expect(await host.next('participant_count'), containsPair('count', 0));
    final count = await host.next('participant_count');
    expect(count['count'], 1);
    expect(count['usernames'], ['ami']);

    // L'etat de lecture de l'hote est bien relaye a l'ami.
    host.send({'type': 'state', 'trackId': 't1', 'isPlaying': true});
    expect(await friend.next('state'), containsPair('trackId', 't1'));

    await friend.close();
    await host.close();
  });

  test('rejoindre une session qui n\'existe pas renvoie une erreur', () async {
    final friend = await _Client.connect(port);
    friend.send({'type': 'join', 'sessionId': 'inconnue', 'username': 'ami'});
    expect(await friend.next('error'),
        containsPair('message', 'session introuvable'));
    await friend.close();
  });
}
