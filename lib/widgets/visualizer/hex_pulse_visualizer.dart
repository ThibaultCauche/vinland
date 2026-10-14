import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../domain/beat_pulse.dart';
import '../../services/audio_visualizer.dart';

/// Grille d'hexagones qui s'allume par vagues depuis [origin] au rythme des
/// basses (mini lecteur et grand lecteur).
///
/// Quand l'analyse audio n'est pas disponible (permission refusee, Windows,
/// lecture sur Chromecast), la grille pulse toute seule, doucement, tant
/// que la musique joue ; a l'arret elle reste allumee faiblement, sans
/// animation.
class HexPulseVisualizer extends StatefulWidget {
  const HexPulseVisualizer({
    super.key,
    required this.visualizer,
    required this.playing,
    this.color,
    this.origin = Alignment.center,
    this.cellRadius = 16,
    this.intensity = 1,
  });

  final AudioVisualizer visualizer;
  final bool playing;

  /// Couleur des hexagones ; vert Vinland par defaut.
  final Color? color;

  /// D'ou partent les vagues.
  final Alignment origin;

  /// Rayon d'un hexagone, en pixels logiques.
  final double cellRadius;

  /// 0..1 : discret derriere le mini lecteur, plein dans le grand lecteur.
  final double intensity;

  static const vinlandGreen = Color(0xFF1DB954);

  /// Couleur tiree de la pochette, toujours (vert seulement sans pochette) :
  /// sa teinte, eclaircie pour se voir sur le fond sombre. Une pochette
  /// terne (noir et blanc...) donne des hexagones gris clair.
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
  State<HexPulseVisualizer> createState() => _HexPulseVisualizerState();
}

class _HexPulseVisualizerState extends State<HexPulseVisualizer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final BeatPulse _beat = BeatPulse();
  final PulseRings _rings = PulseRings();
  final ValueNotifier<int> _frame = ValueNotifier(0);
  Duration _last = Duration.zero;
  double _idleLevel = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    widget.visualizer.attach();
    _syncTicker();
  }

  @override
  void didUpdateWidget(HexPulseVisualizer old) {
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
      final beat =
          _beat.add(bass: levels.bass, mid: levels.mid, elapsed: elapsed);
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

    _frame.value++;
    if (!widget.playing && _rings.rings.isEmpty && _beat.level <= 0.01) {
      _ticker.stop();
    }
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
        painter: _HexPainter(
          repaint: _frame,
          rings: _rings,
          level: () => math.max(_beat.level, _idleLevel),
          color: widget.color ?? HexPulseVisualizer.vinlandGreen,
          origin: widget.origin,
          cellRadius: widget.cellRadius,
          intensity: widget.intensity,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  _HexPainter({
    required Listenable repaint,
    required this.rings,
    required this.level,
    required this.color,
    required this.origin,
    required this.cellRadius,
    required this.intensity,
  }) : super(repaint: repaint);

  final PulseRings rings;
  final double Function() level;
  final Color color;
  final Alignment origin;
  final double cellRadius;
  final double intensity;

  static final Map<double, Path> _hexCache = {};

  /// Hexagone « pointe en haut » centre sur (0, 0), legerement plus petit
  /// que sa case pour laisser un joint sombre entre les alveoles.
  static Path _hex(double r) => _hexCache.putIfAbsent(r, () {
        final path = Path();
        final inner = r * 0.88;
        for (var i = 0; i < 6; i++) {
          final a = math.pi / 6 + i * math.pi / 3;
          final p = Offset(inner * math.cos(a), inner * math.sin(a));
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        return path..close();
      });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final r = cellRadius;
    final w = math.sqrt(3) * r;
    final h = 1.5 * r;
    final center = origin.alongSize(size);
    final maxDist = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - center).distance).reduce(math.max);
    final lvl = level();
    final hex = _hex(r);

    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, r / 24);

    final rows = (size.height / h).ceil() + 1;
    final cols = (size.width / w).ceil() + 1;
    for (var row = -1; row < rows; row++) {
      final y = row * h;
      final shift = row.isOdd ? w / 2 : 0.0;
      for (var col = -1; col < cols; col++) {
        final c = Offset(col * w + shift, y);
        final d = (c - center).distance / maxDist;
        // Lueur de fond qui respire avec le niveau, plus forte au centre,
        // plus les vagues qui passent.
        final glow = rings.glowAt(d) * 0.7 + lvl * 0.25 * (1 - d);
        final b = (0.06 + glow).clamp(0.0, 1.0) * intensity;
        canvas.save();
        canvas.translate(c.dx, c.dy);
        fill.color = color.withValues(alpha: b * 0.14);
        canvas.drawPath(hex, fill);
        stroke.color = color.withValues(alpha: 0.04 + b * 0.45);
        canvas.drawPath(hex, stroke);
        canvas.restore();
      }
    }

    // Halo au centre, pour l'effet « lumiere sous la grille » de la video.
    final halo = Paint()
      ..shader = ui.Gradient.radial(
        center,
        maxDist * 0.6,
        [
          color.withValues(alpha: (0.05 + lvl * 0.12) * intensity),
          color.withValues(alpha: 0),
        ],
      );
    canvas.drawRect(Offset.zero & size, halo);
  }

  @override
  bool shouldRepaint(_HexPainter old) =>
      old.color != color ||
      old.origin != origin ||
      old.cellRadius != cellRadius ||
      old.intensity != intensity;
}
