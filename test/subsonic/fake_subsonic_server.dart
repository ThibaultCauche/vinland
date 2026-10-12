import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinland/data/subsonic/subsonic_client.dart';

/// Reponse Subsonic enregistree dans test/fixtures/subsonic/.
String fixture(String name) =>
    File('test/fixtures/subsonic/$name.json').readAsStringSync();

/// Reponse `ok` minimale avec [payload] en plus.
String okResponse([Map<String, Object?> payload = const {}]) => jsonEncode({
      'subsonic-response': {
        'status': 'ok',
        'version': '1.16.1',
        'type': 'navidrome',
        ...payload,
      }
    });

/// Faux Navidrome : chaque endpoint (ex. `search3.view`) a son handler, et
/// toutes les requetes recues sont gardees pour les assertions.
class FakeSubsonicServer {
  final requests = <http.Request>[];
  final handlers = <String, http.Response Function(http.Request)>{};

  late final client = MockClient((request) async {
    requests.add(request);
    final endpoint = request.url.pathSegments.last;
    final handler = handlers[endpoint];
    if (handler == null) {
      return http.Response('<html>introuvable</html>', 404);
    }
    return handler(request);
  });

  void on(String endpoint, http.Response Function(http.Request) handler) =>
      handlers[endpoint] = handler;

  void json(String endpoint, String body) =>
      on(endpoint, (_) => http.Response(body, 200));

  List<http.Request> to(String endpoint) =>
      requests.where((r) => r.url.pathSegments.last == endpoint).toList();

  /// Client pret a l'emploi, sans delai entre les essais.
  SubsonicClient subsonicClient({int maxRetries = 2}) => SubsonicClient(
        httpClient: client,
        maxRetries: maxRetries,
        sleep: (_) async {},
      )
        ..baseUrl = 'https://nas.example'
        ..authParams = const {'u': 'thibault', 't': 'jeton', 's': 'sel'};
}

/// [count] titres Subsonic generes (pour la pagination).
List<Map<String, Object?>> fakeSongs(int count, {int from = 0}) => [
      for (var i = from; i < from + count; i++)
        {
          'id': 'tr-$i',
          'title': 'Titre $i',
          'artist': 'Artiste ${i % 7}',
          'album': 'Album ${i ~/ 12}',
          'albumId': 'al-${i ~/ 12}',
          'duration': 200,
        }
    ];
