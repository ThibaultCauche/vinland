// Point d'entree du relais Jam : toute la logique est dans lib/relay.dart
// (testable sans lancer de processus, voir test/relay_test.dart) et, pour le
// mode Soiree, dans lib/party/ (voir docs/soiree-protocole.md).
import 'dart:async';
import 'dart:io';

import 'package:jam_relay/party/catalog.dart';
import 'package:jam_relay/party/party_hub.dart';
import 'package:jam_relay/party/party_token.dart';
import 'package:jam_relay/relay.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Catalogue Navidrome du relais (recherche des invites, verification des
/// hotes) : seulement si les trois variables sont fournies.
PartyHub _partyHubFromEnvironment(Map<String, String> env) {
  final url = env['NAVIDROME_URL'] ?? '';
  final user = env['NAVIDROME_USER'] ?? '';
  final password = env['NAVIDROME_PASSWORD'] ?? '';
  final ttlHours = int.tryParse(env['PARTY_TTL_HOURS'] ?? '') ?? 6;
  return PartyHub(
    signer: PartyTokenSigner.random(),
    catalog: url.isEmpty || user.isEmpty || password.isEmpty
        ? null
        : NavidromeCatalog(baseUrl: url, user: user, password: password),
    limits: PartyLimits(
      ttl: Duration(hours: ttlHours.clamp(1, 24)),
      allowAnonymousHost: env['PARTY_ALLOW_ANON_HOST'] == '1',
    ),
  );
}

/// GET /jam/party/cover/<coverId>?size=300, jeton en `Authorization:
/// Bearer`. Sous /jam pour passer par la meme route tailscale serve.
Future<Response> _partyCover(
    PartyHub party, Request request, String coverId) async {
  final auth = request.headers['authorization'] ?? '';
  final token = auth.startsWith('Bearer ') ? auth.substring(7) : null;
  final size = int.tryParse(request.url.queryParameters['size'] ?? '') ?? 300;
  final (status, image) = await party.cover(token, coverId, size);
  if (image == null) return Response(status);
  return Response.ok(image.bytes, headers: {
    'content-type': image.contentType,
    'cache-control': 'private, max-age=3600',
  });
}

void main(List<String> args) async {
  final env = Platform.environment;
  final port = int.tryParse(env['PORT'] ?? '') ?? 8765;
  final party = _partyHubFromEnvironment(env);
  Timer.periodic(const Duration(seconds: 30), (_) => party.sweep());
  final relay =
      JamRelay(limits: RelayLimits.fromEnvironment(env), party: party);

  final server = await shelf_io.serve(
    // Un seul chemin ("/jam") : c'est celui que tailscale serve doit router
    // vers ce service, sur le meme hostname Funnel que Navidrome.
    (Request request) {
      if (request.url.path == 'jam' || request.url.path == '') {
        return relay.handler(request);
      }
      final cover = RegExp(r'^(?:jam/)?party/cover/([^/]+)$')
          .firstMatch(request.url.path);
      if (cover != null && request.method == 'GET') {
        return _partyCover(party, request, cover.group(1)!);
      }
      return Response.notFound('not found');
    },
    InternetAddress.anyIPv4,
    port,
  );
  stderr.writeln('jam_relay: en ecoute sur :${server.port}');
}
