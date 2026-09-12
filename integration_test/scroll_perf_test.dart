import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vinland/main.dart' as app;

/// Diagnostic ponctuel des perfs de scroll de la home desktop (voir la
/// demande utilisateur : equivalent Lighthouse pour l'app Windows). Lance
/// la vraie app (app.main(), meme identite Windows donc memes identifiants
/// NAS en cache que l'app normale), attend l'arrivee sur la home, puis
/// mesure 5 flings via watchPerformance -- mesure basee sur les vrais
/// FrameTiming du moteur (build + raster par frame), pas une simulation.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop home scroll performance', (tester) async {
    app.main();

    // Le login (identifiants caches) + la premiere synchro NAS peuvent
    // prendre plusieurs secondes avant que la home desktop n'apparaisse.
    final scrollFinder = find.byKey(const Key('desktopHomeScrollView'));
    var attempts = 0;
    while (scrollFinder.evaluate().isEmpty && attempts < 30) {
      await tester.pump(const Duration(seconds: 1));
      attempts++;
    }

    expect(
      scrollFinder,
      findsOneWidget,
      reason: 'La home desktop (ListView "desktopHomeScrollView") n\'est '
          'jamais apparue apres ${attempts}s -- probablement bloque sur '
          'l\'ecran de login (identifiants NAS pas caches pour ce build) '
          'plutot qu\'un vrai souci de perf.',
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
    debugPrint('==================== SCROLL PERF SUMMARY ====================');
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
        '===============================================================');
  });
}
