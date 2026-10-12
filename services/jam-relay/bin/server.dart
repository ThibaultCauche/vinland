// Point d'entree du relais Jam : toute la logique est dans lib/relay.dart
// (testable sans lancer de processus, voir test/relay_test.dart).
import 'dart:io';

import 'package:jam_relay/relay.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

void main(List<String> args) async {
  final env = Platform.environment;
  final port = int.tryParse(env['PORT'] ?? '') ?? 8765;
  final relay = JamRelay(limits: RelayLimits.fromEnvironment(env));

  final server = await shelf_io.serve(
    // Un seul chemin ("/jam") : c'est celui que tailscale serve doit router
    // vers ce service, sur le meme hostname Funnel que Navidrome.
    (Request request) {
      if (request.url.path == 'jam' || request.url.path == '') {
        return relay.handler(request);
      }
      return Response.notFound('not found');
    },
    InternetAddress.anyIPv4,
    port,
  );
  stderr.writeln('jam_relay: en ecoute sur :${server.port}');
}
