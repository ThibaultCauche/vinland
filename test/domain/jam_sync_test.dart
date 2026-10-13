import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/domain/jam_sync.dart';

const ms = Duration(milliseconds: 1);

void main() {
  group('horloge du relais', () {
    test(
        'un telephone en retard de 2 min sur le relais retrouve l\'heure '
        'du relais', () {
      // Le telephone envoie a 1000 (son heure), le relais repond a
      // 121040 (la sienne), la reponse arrive a 1080 : 40 ms par trajet.
      const sample =
          ClockSample(sentMs: 1000, relayMs: 121040, receivedMs: 1080);
      expect(sample.roundTripMs, 80);
      expect(sample.offsetMs, 120000);
    });

    test('une mesure prise pendant un pic reseau ne fausse pas l\'ecart', () {
      final samples = [
        const ClockSample(sentMs: 0, relayMs: 5020, receivedMs: 40),
        const ClockSample(sentMs: 100, relayMs: 5120, receivedMs: 140),
        // Retour bloque 900 ms dans le Wi-Fi : ecart faux de 450 ms.
        const ClockSample(sentMs: 200, relayMs: 5220, receivedMs: 1140),
        const ClockSample(sentMs: 1200, relayMs: 6222, receivedMs: 1244),
        const ClockSample(sentMs: 1300, relayMs: 6318, receivedMs: 1336),
      ];
      final estimate = ClockEstimate.fromSamples(samples);
      expect(estimate.offsetMs, 5000);
      expect(estimate.roundTripMs, 40);
      expect(estimate.isKnown, isTrue);
    });

    test('un relais qui ne repond pas aux pings laisse les horloges telles',
        () {
      final estimate = ClockEstimate.fromSamples([]);
      expect(estimate.offsetMs, 0);
      expect(estimate.isKnown, isFalse);
    });
  });

  group('correction de l\'ecart', () {
    const expected = Duration(seconds: 60);

    SyncAction decide(int driftMs) =>
        decideSync(ms * driftMs, expected: expected);

    test('plus d\'une seconde d\'ecart : seek a la position de l\'hote', () {
      final action = decide(1500);
      expect(action, isA<SyncSeek>());
      expect((action as SyncSeek).target, expected);
      expect(decide(-1200), isA<SyncSeek>(), reason: 'en avance aussi');
    });

    test('300 ms de retard : on accelere de 3 % au plus, sans seek', () {
      final action = decide(300);
      expect(action, isA<SyncNudge>());
      expect((action as SyncNudge).speed, closeTo(1.03, 1e-9));
    });

    test('80 ms d\'avance : on ralentit juste assez', () {
      final action = decide(-80) as SyncNudge;
      expect(action.speed, closeTo(0.98, 1e-9));
    });

    test('moins de 40 ms : on ne touche a rien', () {
      expect(decide(30), isA<SyncHold>());
      expect(decide(-39), isA<SyncHold>());
      expect(decide(0), isA<SyncHold>());
    });
  });

  group('journal', () {
    SyncLogEntry entry(int driftMs) => SyncLogEntry(
          at: DateTime(2026),
          driftMs: driftMs,
          action: const SyncHold(),
          clockOffsetMs: 0,
          roundTripMs: 40,
        );

    test('garde seulement les dernieres mesures', () {
      final log = SyncLog(capacity: 3);
      for (var i = 0; i < 5; i++) {
        log.add(entry(i));
      }
      expect(log.entries.map((e) => e.driftMs), [2, 3, 4]);
    });

    test('ecart moyen en valeur absolue', () {
      final log = SyncLog()
        ..add(entry(-30))
        ..add(entry(10));
      expect(log.averageAbsDriftMs(), 20);
      expect(SyncLog().averageAbsDriftMs(), isNull);
    });

    test('libelle lisible de chaque decision', () {
      expect(entry(0).actionLabel, 'rien');
      expect(
          SyncLogEntry(
            at: DateTime(2026),
            driftMs: 300,
            action: const SyncNudge(1.03),
            clockOffsetMs: 0,
            roundTripMs: 40,
          ).actionLabel,
          'vitesse 3.0 %');
    });
  });
}
