import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/domain/beat_pulse.dart';

const _frame = Duration(milliseconds: 50);

/// Rejoue [seconds] de mesures : une grosse caisse toutes les [beatEvery]
/// mesures, du bruit de fond bas le reste du temps.
List<double?> _play(BeatPulse pulse,
    {required int frames,
    int beatEvery = 10,
    double kick = 0.8,
    double floor = 0.2}) {
  return [
    for (var i = 0; i < frames; i++)
      pulse.add(
        bass: i % beatEvery == 0 ? kick : floor,
        mid: 0.3,
        elapsed: _frame,
      ),
  ];
}

void main() {
  group('BeatPulse', () {
    test('detecte une grosse caisse reguliere', () {
      final pulse = BeatPulse();
      final beats = _play(pulse, frames: 100).whereType<double>().length;
      // 100 mesures, un coup toutes les 10 : ~10 coups (le premier peut
      // manquer le temps que la moyenne s'installe).
      expect(beats, inInclusiveRange(9, 10));
    });

    test('ne voit aucun coup dans un son continu', () {
      final pulse = BeatPulse();
      _play(pulse, frames: 20, beatEvery: 1, kick: 0.5);
      final later = _play(pulse, frames: 60, beatEvery: 1, kick: 0.5);
      expect(later.whereType<double>(), isEmpty);
    });

    test('ignore le silence', () {
      final pulse = BeatPulse();
      final beats = [
        for (var i = 0; i < 50; i++)
          pulse.add(bass: 0, mid: 0, elapsed: _frame),
      ];
      expect(beats.whereType<double>(), isEmpty);
      expect(pulse.level, 0);
    });

    test('deux coups trop rapproches n en font qu un', () {
      final pulse = BeatPulse();
      _play(pulse, frames: 40);
      // Coups toutes les 2 mesures = toutes les 100 ms, sous minBeatGap.
      final fast =
          _play(pulse, frames: 40, beatEvery: 2).whereType<double>().length;
      expect(fast, lessThanOrEqualTo(40 * 50 ~/ 280 + 1));
    });

    test('suit aussi un morceau calme (niveau rapporte au pic recent)', () {
      final pulse = BeatPulse();
      final beats = _play(pulse, frames: 100, kick: 0.25, floor: 0.06)
          .map((b) => b ?? 0)
          .toList();
      expect(beats.where((b) => b > 0).length, greaterThanOrEqualTo(8));
      expect(pulse.level, greaterThan(0));
    });

    test('repere les coups sur des basses ecrasees par l echelle log', () {
      // Comme mesure sur le telephone : basse continue vers 0,85, grosse
      // caisse a 0,95, une mesure toutes les 50 ms mais lue a chaque image
      // (~16 ms), donc la meme valeur repetee trois fois.
      final pulse = BeatPulse();
      var beats = 0;
      for (var i = 0; i < 300; i++) {
        final sample = i ~/ 3;
        final bass = sample % 8 == 0 ? 0.95 : 0.85 + (sample % 3) * 0.01;
        final hit = pulse.add(
          bass: bass,
          mid: 0.6,
          elapsed: const Duration(microseconds: 16667),
        );
        if (hit != null) beats++;
      }
      // 100 mesures, un coup toutes les 8 : ~12 coups.
      expect(beats, inInclusiveRange(10, 13));
    });

    test('le niveau reste entre 0 et 1', () {
      final pulse = BeatPulse();
      for (var i = 0; i < 200; i++) {
        pulse.add(bass: i.isEven ? 1.5 : -1, mid: 2, elapsed: _frame);
        expect(pulse.level, inInclusiveRange(0, 1));
      }
    });
  });

  group('PulseRings', () {
    test('une vague passe du centre vers le bord puis s eteint', () {
      final rings = PulseRings(lifetime: 1.6)..spawn(1);
      expect(rings.glowAt(0), greaterThan(rings.glowAt(0.8)));
      rings.advance(1.0);
      expect(rings.glowAt(0.7), greaterThan(rings.glowAt(0)));
      rings.advance(1.0);
      expect(rings.rings, isEmpty);
      expect(rings.glowAt(0.5), 0);
    });

    test('garde un nombre limite de vagues', () {
      final rings = PulseRings(maxRings: 3);
      for (var i = 0; i < 10; i++) {
        rings.spawn(1);
      }
      expect(rings.rings, hasLength(3));
      expect(rings.glowAt(0), lessThanOrEqualTo(1));
    });
  });
}
