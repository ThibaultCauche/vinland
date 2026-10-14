import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/controllers/cast_controller.dart';
import 'package:vinland/services/cast/cast_discovery.dart';
import 'package:vinland/services/cast/cast_player_engine.dart';
import 'package:vinland/services/player_engine.dart';
import 'package:vinland/services/routed_player_engine.dart';

import '../fakes/fake_cast_receiver.dart';
import '../fakes/fake_player_engine.dart';

class _FakeScanner implements CastScanner {
  final controller = StreamController<List<CastDevice>>.broadcast();
  bool stopped = false;

  @override
  Stream<List<CastDevice>> scan() {
    stopped = false;
    return controller.stream;
  }

  @override
  Future<void> stop() async => stopped = true;
}

class _FakeOutput implements OutputSwitch {
  _FakeOutput(this.localEngine) : activeEngine = localEngine;

  @override
  final PlayerEngine localEngine;
  @override
  PlayerEngine activeEngine;
  final List<String> log = [];
  bool failNext = false;

  @override
  Future<void> switchOutput(PlayerEngine target, {bool resume = true}) async {
    activeEngine = target;
    log.add('${identical(target, localEngine) ? 'local' : 'cast'}'
        '${resume ? '' : ' (pause)'}');
    if (failNext) {
      failNext = false;
      throw StateError('titre refuse');
    }
  }
}

const _salon = CastDevice(id: 'Chromecast-1', name: 'Salon', host: '10.0.0.5');

void main() {
  late _FakeScanner scanner;
  late _FakeOutput output;
  late List<FakeCastReceiver> receivers;
  late CastController cast;

  setUp(() {
    scanner = _FakeScanner();
    output = _FakeOutput(FakePlayerEngine());
    receivers = [];
    cast = CastController(
      output: output,
      scanner: scanner,
      connector: (device) async {
        final receiver = FakeCastReceiver();
        receivers.add(receiver);
        return CastPlayerEngine.launch(receiver.channel);
      },
    );
  });

  tearDown(() => cast.dispose());

  test('la recherche remonte les appareils trouves', () async {
    cast.startScan();
    scanner.controller.add([_salon]);
    await Future<void>.delayed(Duration.zero);
    expect(cast.devices, [_salon]);
    await cast.stopScan();
    expect(scanner.stopped, isTrue);
  });

  test('connecter passe la lecture sur la Chromecast', () async {
    expect(await cast.connect(_salon), isTrue);
    expect(cast.isCasting, isTrue);
    expect(cast.device, _salon);
    expect(cast.volume, 0.4);
    expect(output.log, ['cast']);
  });

  test('deconnecter revient sur l\'appareil, en pause', () async {
    await cast.connect(_salon);
    await cast.disconnect();
    expect(cast.isCasting, isFalse);
    expect(output.log, ['cast', 'local (pause)']);
    expect(receivers.single.types, contains('STOP'));
  });

  test('un titre refuse ramene sur l\'appareil avec un message', () async {
    output.failNext = true;
    expect(await cast.connect(_salon), isFalse);
    expect(cast.isCasting, isFalse);
    expect(output.log, ['cast', 'local (pause)']);
    expect(cast.message, contains('Salon'));
  });

  test('une Chromecast injoignable laisse la lecture ou elle est', () async {
    final failing = CastController(
      output: output,
      scanner: scanner,
      connector: (_) async => throw const SocketLikeError(),
    );
    expect(await failing.connect(_salon), isFalse);
    expect(output.log, isEmpty);
    expect(failing.message, 'Impossible de joindre Salon.');
    failing.dispose();
  });

  test('la tele qui coupe ramene la lecture sur l\'appareil', () async {
    await cast.connect(_salon);
    receivers.single.closeApp();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(cast.isCasting, isFalse);
    expect(output.log, ['cast', 'local (pause)']);
    expect(cast.message, contains('arrêtée'));
  });

  test('le volume part vers la Chromecast', () async {
    await cast.connect(_salon);
    await cast.setVolume(0.8);
    await Future<void>.delayed(Duration.zero);
    expect(receivers.single.volume, 0.8);
  });
}

class SocketLikeError implements Exception {
  const SocketLikeError();
}
