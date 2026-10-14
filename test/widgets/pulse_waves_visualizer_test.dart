import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/services/audio_visualizer.dart';
import 'package:vinland/widgets/visualizer/pulse_waves_visualizer.dart';

Widget _host(AudioVisualizer v, {required bool playing}) => MaterialApp(
      home: SizedBox(
        width: 360,
        height: 640,
        child: PulseWavesVisualizer(visualizer: v, playing: playing),
      ),
    );

void main() {
  testWidgets('anime la grille pendant la lecture, sans erreur',
      (tester) async {
    final v = AudioVisualizer.disabled();
    await tester.pumpWidget(_host(v, playing: true));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('s arrete d animer apres la pause', (tester) async {
    final v = AudioVisualizer.disabled();
    await tester.pumpWidget(_host(v, playing: true));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(_host(v, playing: false));
    // Les dernieres vagues s'eteignent, puis plus rien ne tourne.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.hasRunningAnimations, isFalse);
  });

  test('couleur : toujours celle de la pochette, vert sans pochette', () {
    expect(PulseWavesVisualizer.colorFromCover(null),
        PulseWavesVisualizer.vinlandGreen);
    final grey = HSLColor.fromColor(
        PulseWavesVisualizer.colorFromCover(const Color(0xFF303030)));
    expect(grey.saturation, lessThan(0.05));
    expect(grey.lightness, closeTo(0.65, 0.01));
    final blue = HSLColor.fromColor(
        PulseWavesVisualizer.colorFromCover(const Color(0xFF0A2A6A)));
    expect(blue.hue, closeTo(220, 5));
    expect(blue.lightness, closeTo(0.65, 0.01));
  });
}
