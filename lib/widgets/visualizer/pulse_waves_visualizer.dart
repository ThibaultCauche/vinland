import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../domain/beat_pulse.dart';
import '../../services/audio_visualizer.dart';

/// Vagues de lumiere douces qui partent de [origin] au rythme des basses,
/// sur un halo qui respire avec la musique (mini lecteur et grand lecteur).
///
/// Quand l'analyse audio n'est pas disponible (permission refusee,
/// lecture sur Chromecast), seul le halo respire lentement tant que la
/// musique joue, sans fausses vagues ; a l'arret tout s'eteint.
class PulseWavesVisualizer extends StatefulWidget {
  const PulseWavesVisualizer({
    super.key,
    required this.visualizer,
    required this.playing,
    this.color,
    this.origin = Alignment.center,
    this.originKey,
    this.intensity = 1,
  });

  final AudioVisualizer visualizer;
  final bool playing;

  /// Couleur des vagues ; vert Vinland par defaut.
  final Color? color;

  /// D'ou partent les vagues.
  final Alignment origin;

  /// Si donne, les vagues partent du centre de ce widget (la pochette du
  /// grand lecteur), ou qu'il soit a l'ecran ; sinon de [origin].
  final GlobalKey? originKey;

  /// 0..1 : discret derriere le mini lecteur, plein dans le grand lecteur.
  final double intensity;

  static const vinlandGreen = Color(0xFF1DB954);

  /// Couleur tiree de la pochette, toujours (vert seulement sans pochette) :
  /// sa teinte, eclaircie pour se voir sur le fond sombre. Une pochette
  /// terne (noir et blanc...) donne des vagues gris clair.
  static Color colorFromCover(Color? dominant) {
    if (dominant == null) return vinlandGreen;
    final hsl = HSLColor.fromColor(dominant);
    return hsl
        .withSaturation(hsl.saturation < 0.15
            ? hsl.saturation
            : math.max(hsl.saturation, 0.5))
        .withLightness(0.65)
        .toColor();
  }

  @override
  State<PulseWavesVisualizer> createState() => _PulseWavesVisualizerState();
}

class _PulseWavesVisualizerState extends State<PulseWavesVisualizer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final BeatPulse _beat = BeatPulse();
  final PulseRings _rings = PulseRings();
  final ValueNotifier<int> _frame = ValueNotifier(0);
  Duration _last = Duration.zero;
  double _idleLevel = 0;
  Offset? _center;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    widget.visualizer.attach();
    _syncTicker();
  }

  @override
  void didUpdateWidget(PulseWavesVisualizer old) {
    super.didUpdateWidget(old);
    if (old.visualizer != widget.visualizer) {
      old.visualizer.detach();
      widget.visualizer.attach();
    }
    _syncTicker();
  }

  /// A l'arret on laisse les dernieres vagues s'eteindre, puis plus aucune
  /// image n'est calculee.
  void _syncTicker() {
    if (widget.playing || _rings.rings.isNotEmpty || _beat.level > 0.01) {
      if (!_ticker.isActive) {
        _last = Duration.zero;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration now) {
    final elapsed = _last == Duration.zero ? Duration.zero : now - _last;
    _last = now;
    final dt = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    _rings.advance(dt);

    final levels = widget.playing ? widget.visualizer.latest : null;
    if (levels != null) {
      _idleLevel = 0;
      final beat = _beat.add(
        bass: levels.bass,
        mid: levels.mid,
        loudness: levels.loudness,
        elapsed: elapsed,
      );
      if (beat != null) _rings.spawn(0.35 + 0.65 * beat);
    } else {
      // Sans analyse du son : pas de fausses vagues a rythme fixe (elles
      // ne collaient jamais a la musique), juste une lente respiration.
      _beat.add(bass: 0, mid: 0, elapsed: elapsed);
      if (widget.playing) {
        _idleLevel = 0.12 + 0.08 * math.sin(now.inMilliseconds / 1400);
      } else {
        _idleLevel = math.max(0, _idleLevel - dt);
      }
    }

    _center = _originCenter();
    _frame.value++;
    if (!widget.playing && _rings.rings.isEmpty && _beat.level <= 0.01) {
      _ticker.stop();
    }
  }

  /// Centre du widget [PulseWavesVisualizer.originKey], dans le repere du
  /// visuel.
  Offset? _originCenter() {
    final target = widget.originKey?.currentContext?.findRenderObject();
    final self = context.findRenderObject();
    if (target is! RenderBox || self is! RenderBox) return null;
    if (!target.hasSize || !self.hasSize || !target.attached) return null;
    return self
        .globalToLocal(target.localToGlobal(target.size.center(Offset.zero)));
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.visualizer.detach();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _WavesPainter(
          repaint: _frame,
          rings: _rings,
          level: () => math.max(_beat.level, _idleLevel),
          color: widget.color ?? PulseWavesVisualizer.vinlandGreen,
          origin: widget.origin,
          center: () => _center,
          intensity: widget.intensity,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _WavesPainter extends CustomPainter {
  _WavesPainter({
    required Listenable repaint,
    required this.rings,
    required this.level,
    required this.color,
    required this.origin,
    required this.center,
    required this.intensity,
  }) : super(repaint: repaint);

  final PulseRings rings;
  final double Function() level;
  final Color color;
  final Alignment origin;
  final Offset? Function() center;
  final double intensity;

  /// Epaisseur d'une vague, en part de la distance au bord le plus loin.
  static const _waveWidth = 0.16;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = this.center() ?? origin.alongSize(size);
    final maxDist = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - center).distance).reduce(math.max);
    final rect = Offset.zero & size;
    final lvl = level();
    final transparent = color.withValues(alpha: 0);

    // Halo qui respire avec le niveau de la musique.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          maxDist * (0.4 + lvl * 0.3),
          [
            color.withValues(alpha: (0.06 + lvl * 0.38) * intensity),
            transparent,
          ],
        ),
    );

    // Chaque coup de basse : un anneau de lumiere floue qui s'eloigne et
    // s'estompe (degrade radial transparent > couleur > transparent).
    for (final ring in rings.rings) {
      final t = ring.age / rings.lifetime;
      final front = t * 1.15;
      final alpha = ring.strength * (1 - t) * (1 - t) * 0.42 * intensity;
      if (alpha <= 0.005) continue;
      final outer = front + _waveWidth;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            maxDist * outer,
            [
              transparent,
              transparent,
              color.withValues(alpha: alpha),
              transparent
            ],
            [
              0,
              (math.max(0, front - _waveWidth) / outer).clamp(0.0, 1.0),
              (front / outer).clamp(0.0, 1.0),
              1,
            ],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_WavesPainter old) =>
      old.color != color || old.origin != origin || old.intensity != intensity;
}
