import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/controllers/cast_controller.dart';
import 'package:vinland/services/cast/cast_discovery.dart';
import 'package:vinland/services/player_engine.dart';
import 'package:vinland/services/routed_player_engine.dart';
import 'package:vinland/widgets/player/cast_devices_section.dart';

import '../fakes/fake_player_engine.dart';

class _Scanner implements CastScanner {
  final controller = StreamController<List<CastDevice>>.broadcast();
  bool stopped = false;
  @override
  Stream<List<CastDevice>> scan() => controller.stream;
  @override
  Future<void> stop() async => stopped = true;
}

class _Output implements OutputSwitch {
  @override
  final PlayerEngine localEngine = FakePlayerEngine();
  @override
  PlayerEngine get activeEngine => localEngine;
  @override
  Future<void> switchOutput(PlayerEngine target, {bool resume = true}) async {}
}

void main() {
  testWidgets(
      'liste les Chromecast trouvees et arrete la recherche a la '
      'fermeture', (tester) async {
    final scanner = _Scanner();
    final cast = CastController(output: _Output(), scanner: scanner);
    // Un autre ecouteur (le bouton Peripheriques) : ouvrir et fermer le
    // menu ne doit pas le reconstruire pendant un build.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ListenableBuilder(
            listenable: cast,
            builder: (_, __) => Icon(deviceMenuIcon(cast)),
          ),
          CastDevicesSection(cast: cast),
        ]),
      ),
    ));
    expect(find.text('Cet appareil'), findsOneWidget);
    expect(find.text('Recherche des Chromecast…'), findsOneWidget);

    scanner.controller.add(const [
      CastDevice(id: 'a', name: 'Salon', host: '10.0.0.5', model: 'Chromecast'),
    ]);
    await tester.pump();
    expect(find.text('Salon'), findsOneWidget);
    expect(find.text('Recherche des Chromecast…'), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: ListenableBuilder(
        listenable: cast,
        builder: (_, __) => Icon(deviceMenuIcon(cast)),
      ),
    ));
    await tester.pump();
    expect(scanner.stopped, isTrue);
    cast.dispose();
  });

  testWidgets('sans Chromecast apres quelques secondes, explique pourquoi',
      (tester) async {
    final cast = CastController(output: _Output(), scanner: _Scanner());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CastDevicesSection(cast: cast)),
    ));
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('Aucune Chromecast trouvée'), findsOneWidget);
    expect(find.textContaining('même Wi-Fi'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    cast.dispose();
  });

  test('l\'annonce mDNS donne le nom et prefere l\'IPv4', () {
    final device = CastDevice.fromService(
      serviceName: 'Chromecast-abc',
      addresses: ['fe80::1', '192.168.1.30'],
      port: 8009,
      attributes: {'fn': 'Chambre', 'md': 'Google Nest Mini'},
    )!;
    expect(device.name, 'Chambre');
    expect(device.host, '192.168.1.30');
    expect(device.isSpeaker, isTrue);
    expect(
      CastDevice.fromService(
        serviceName: 'x',
        addresses: const [],
        port: 8009,
        attributes: const {},
      ),
      isNull,
    );
  });
}
