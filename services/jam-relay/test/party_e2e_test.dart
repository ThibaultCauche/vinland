// Critere de fin de la session 16 : le client en ligne de commande
// (bin/party_cli.dart) rejoint une soiree et propose un titre qui arrive
// dans la file de l'hote. Tout est reel sauf Navidrome, remplace par un
// petit serveur HTTP qui repond comme l'API Subsonic.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _relayUser = 'relais';
const _relayPassword = 'mot-de-passe-du-relais';
const _hostPassword = 'mot-de-passe-de-thibault';

/// Faux Navidrome : verifie le jeton md5 comme le vrai et note les
/// requetes recues.
Future<HttpServer> _fakeNavidrome(List<Uri> requests) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    requests.add(request.uri);
    final q = request.uri.queryParameters;
    final password = q['u'] == _relayUser
        ? _relayPassword
        : q['u'] == 'thibault'
            ? _hostPassword
            : null;
    final ok = password != null &&
        q['t'] ==
            md5.convert(utf8.encode(password + (q['s'] ?? ''))).toString();
    final response = request.response;
    if (request.uri.path == '/rest/getCoverArt' && ok) {
      response.headers.contentType = ContentType('image', 'jpeg');
      response.add([0xFF, 0xD8, int.parse(q['size']!) % 256]);
      await response.close();
      return;
    }
    final song = {
      'id': 'tr-42',
      'title': 'One More Time',
      'artist': 'Daft Punk',
      'album': 'Discovery',
      'duration': 320,
      'coverArt': 'al-7',
    };
    final body = <String, dynamic>{'status': ok ? 'ok' : 'failed'};
    if (ok && request.uri.path == '/rest/search3') {
      body['searchResult3'] = {
        'song': [song]
      };
    }
    if (ok && request.uri.path == '/rest/getSong' && q['id'] == 'tr-42') {
      body['song'] = song;
    }
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode({'subsonic-response': body}));
    await response.close();
  });
  return server;
}

Future<(Process, int)> _startRelay(Map<String, String> env) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', 'bin/server.dart'],
    environment: {'PORT': '0', ...env},
  );
  final ready = Completer<int>();
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    final match = RegExp(r'en ecoute sur :(\d+)').firstMatch(line);
    if (match != null && !ready.isCompleted) {
      ready.complete(int.parse(match.group(1)!));
    }
  });
  return (process, await ready.future.timeout(const Duration(seconds: 60)));
}

Future<ProcessResult> _cli(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/party_cli.dart', ...args],
      stdoutEncoding: utf8,
    );

void main() {
  late HttpServer navidrome;
  late List<Uri> navidromeRequests;
  late Process relay;
  late int port;

  setUpAll(() async {
    navidromeRequests = [];
    navidrome = await _fakeNavidrome(navidromeRequests);
    (relay, port) = await _startRelay({
      'NAVIDROME_URL': 'http://127.0.0.1:${navidrome.port}',
      'NAVIDROME_USER': _relayUser,
      'NAVIDROME_PASSWORD': _relayPassword,
    });
  });

  tearDownAll(() async {
    relay.kill();
    await navidrome.close(force: true);
  });

  test(
      "le client en ligne de commande propose un titre qui arrive dans la file "
      "de l'hote", () async {
    final url = 'ws://127.0.0.1:$port/jam';
    final host = WebSocketChannel.connect(Uri.parse(url));
    await host.ready;
    final hostMessages = host.stream
        .map((raw) => jsonDecode(raw as String) as Map<String, dynamic>)
        .asBroadcastStream();
    final queueWithSong = hostMessages.firstWhere(
        (m) => m['type'] == 'queue_state' && (m['items'] as List).isNotEmpty);
    final joined = hostMessages.firstWhere((m) => m['type'] == 'party_joined');
    const salt = 'abc123';
    host.sink.add(jsonEncode({
      'type': 'party_create',
      'v': 1,
      'name': 'Anniv',
      'hostName': 'Thibault',
      'auth': {
        'u': 'thibault',
        't': md5.convert(utf8.encode(_hostPassword + salt)).toString(),
        's': salt,
      },
    }));
    final code =
        (await joined.timeout(const Duration(seconds: 10)))['code'] as String;

    final search = await _cli(['search', url, code, 'Lea', 'daft', 'punk']);
    expect(search.exitCode, 0, reason: '${search.stdout}${search.stderr}');
    expect(search.stdout, contains('tr-42  Daft Punk - One More Time'));
    // Rien du compte du relais ne doit arriver jusqu'a l'invite.
    expect(search.stdout, isNot(contains(_relayUser)));
    expect(search.stdout, isNot(contains('127.0.0.1:${navidrome.port}')));

    final suggest = await _cli(['suggest', url, code, 'Lea', 'tr-42']);
    expect(suggest.exitCode, 0, reason: '${suggest.stdout}${suggest.stderr}');

    final queue = await queueWithSong.timeout(const Duration(seconds: 10));
    final item = (queue['items'] as List).single as Map;
    expect(item['songId'], 'tr-42');
    expect(item['title'], 'One More Time');
    expect(item['by'], 'Lea');

    // Pochette redimensionnee, servie par le relais avec le jeton du membre.
    final token = (await joined)['token'] as String;
    final http = HttpClient();
    final request = await http.getUrl(
        Uri.parse('http://127.0.0.1:$port/jam/party/cover/al-7?size=128'));
    request.headers.set('authorization', 'Bearer $token');
    final response = await request.close();
    expect(response.statusCode, 200);
    expect(await response.expand((b) => b).toList(), [0xFF, 0xD8, 128]);
    final anonymous = await (await http
            .getUrl(Uri.parse('http://127.0.0.1:$port/jam/party/cover/al-7')))
        .close();
    expect(anonymous.statusCode, 401);
    http.close();

    await host.sink.close();
  });

  test("un hote avec un mauvais mot de passe ne peut pas ouvrir de soiree",
      () async {
    final result = await _cli([
      'host',
      'ws://127.0.0.1:$port/jam',
      '--user',
      'thibault',
      '--password',
      'faux',
    ]);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('unauthorized'));
  });
}
