import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vinland/main.dart' as app;

/// Equivalent mobile de scroll_perf_test.dart (perf de scroll de la home
/// desktop) : lance la vraie app sur un telephone reel, attend la home
/// mobile (CustomScrollView cle 'mobileHomeScrollView'), puis mesure 5
/// flings via watchPerformance -- mesure basee sur les vrais FrameTiming
/// du moteur (build + raster par frame), pas une simulation.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile home scroll performance', (tester) async {
    app.main();

    final scrollFinder = find.byKey(const Key('mobileHomeScrollView'));
    var attempts = 0;
    while (scrollFinder.evaluate().isEmpty && attempts < 30) {
      await tester.pump(const Duration(seconds: 1));
      attempts++;
    }

    expect(
      scrollFinder,
      findsOneWidget,
      reason: 'La home mobile (CustomScrollView "mobileHomeScrollView") '
          'n\'est jamais apparue apres ${attempts}s -- probablement bloque '
          'sur l\'ecran de login plutot qu\'un vrai souci de perf.',
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await binding.watchPerformance(() async {
      for (var i = 0; i < 5; i++) {
        await tester.fling(scrollFinder, const Offset(0, -600), 3000);
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.pumpAndSettle();
    });

    final summary = binding.reportData!['performance'] as Map<String, dynamic>;
    debugPrint('================ MOBILE SCROLL PERF SUMMARY ================');
    for (final key in [
      'average_frame_build_time_millis',
      '90th_percentile_frame_build_time_millis',
      '99th_percentile_frame_build_time_millis',
      'worst_frame_build_time_millis',
      'missed_frame_build_budget_count',
      'average_frame_rasterizer_time_millis',
      '90th_percentile_frame_rasterizer_time_millis',
      '99th_percentile_frame_rasterizer_time_millis',
      'worst_frame_rasterizer_time_millis',
      'missed_frame_rasterizer_budget_count',
    ]) {
      debugPrint('$key: ${summary[key]}');
    }
    debugPrint(
        '==============================================================');
  });
}
