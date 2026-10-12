// Petit client en ligne de commande du mode Soiree, pour tester le relais
// sans l'app (voir docs/soiree-protocole.md, « Tester sans l'app »).
//
//   dart run bin/party_cli.dart host <ws-url> [--name Soiree] [--as Hote]
//       [--user U --password P]
//   dart run bin/party_cli.dart suggest <ws-url> <code> <pseudo> <songId>
//       [--title "Titre"]
//   dart run bin/party_cli.dart search <ws-url> <code> <pseudo> <recherche>
//
// `host` reste ouvert et affiche la file a chaque changement ; `suggest` et
// `search` rejoignent la soiree, font leur action puis quittent.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _usage = '''
Usage :
  party_cli host <ws-url> [--name Soiree] [--as Hote] [--user U --password P]
  party_cli suggest <ws-url> <code> <pseudo> <songId> [--title "Titre"]
  party_cli search <ws-url> <code> <pseudo> <recherche>''';

Future<void> main(List<String> args) async {
  final positional = <String>[];
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    if (args[i].startsWith('--') && i + 1 < args.length) {
      options[args[i].substring(2)] = args[++i];
    } else {
      positional.add(args[i]);
    }
  }
  if (positional.length < 2) {
    stderr.writeln(_usage);
    exit(64);
  }
  final command = positional[0];
  final channel = WebSocketChannel.connect(Uri.parse(positional[1]));
  await channel.ready;
  final messages = channel.stream
      .map((raw) => jsonDecode(raw as String) as Map<String, dynamic>)
      .asBroadcastStream();
  void send(Map<String, dynamic> m) => channel.sink.add(jsonEncode(m));

  switch (command) {
    case 'host':
      await _host(send, messages, options);
    case 'suggest' when positional.length >= 5:
      await _join(send, messages, positional[2], positional[3]);
      send({
        'type': 'suggest',
        'songId': positional[4],
        'title': options['title'] ?? positional[4],
      });
      final reply = await messages.firstWhere(
          (m) => m['type'] == 'suggested' || m['type'] == 'party_error');
      _exitOnError(reply);
      stdout
          .writeln('Propose : ${reply['songId']} (element ${reply['itemId']})');
    case 'search' when positional.length >= 5:
      await _join(send, messages, positional[2], positional[3]);
      send({
        'type': 'search',
        'requestId': 1,
        'query': positional.sublist(4).join(' '),
      });
      final reply = await messages.firstWhere(
          (m) => m['type'] == 'search_results' || m['type'] == 'party_error');
      _exitOnError(reply);
      for (final song in reply['songs'] as List) {
        stdout.writeln('${song['id']}  ${song['artist']} - ${song['title']}');
      }
    default:
      stderr.writeln(_usage);
      exit(64);
  }
  await channel.sink.close();
}

Future<void> _host(
  void Function(Map<String, dynamic>) send,
  Stream<Map<String, dynamic>> messages,
  Map<String, String> options,
) async {
  final user = options['user'];
  final password = options['password'];
  Map<String, dynamic>? auth;
  if (user != null && password != null) {
    // Meme jeton que l'app : le mot de passe ne part jamais sur le reseau.
    final random = Random.secure();
    final salt =
        List.generate(12, (_) => random.nextInt(16).toRadixString(16)).join();
    auth = {
      'u': user,
      't': md5.convert(utf8.encode(password + salt)).toString(),
      's': salt,
    };
  }
  send({
    'type': 'party_create',
    'v': 1,
    'name': options['name'] ?? 'Soiree test',
    'hostName': options['as'] ?? 'Hote',
    if (auth != null) 'auth': auth,
  });
  final done = Completer<void>();
  messages.listen((m) {
    switch (m['type']) {
      case 'party_joined':
        stdout.writeln('CODE: ${m['code']}');
        stdout.writeln('(Ctrl+C pour terminer)');
      case 'queue_state':
        final items = m['items'] as List;
        stdout.writeln('File (${items.length}, ${m['guestCount']} invites) :');
        for (final item in items) {
          stdout.writeln('  ${item['id']}  ${item['title']}  '
              'par ${item['by']}  score ${item['score']}');
        }
      case 'party_error':
        _exitOnError(m);
      case 'party_ended':
        if (!done.isCompleted) done.complete();
    }
  }, onDone: () {
    if (!done.isCompleted) done.complete();
  });
  await done.future;
}

Future<void> _join(
  void Function(Map<String, dynamic>) send,
  Stream<Map<String, dynamic>> messages,
  String code,
  String name,
) async {
  send({'type': 'party_join', 'v': 1, 'code': code, 'name': name});
  final reply = await messages.firstWhere(
      (m) => m['type'] == 'party_joined' || m['type'] == 'party_error');
  _exitOnError(reply);
  stdout.writeln('Entre dans "${reply['name']}" (${reply['memberId']})');
}

void _exitOnError(Map<String, dynamic> message) {
  if (message['type'] != 'party_error') return;
  stderr.writeln('Erreur ${message['code']} : ${message['message']}');
  exit(1);
}
