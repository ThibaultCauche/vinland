import 'package:flutter/material.dart';

/// Rendu applique a la couleur choisie en mode "Uni" (Parametres >
/// Personnalisation), partage entre mobile et desktop. La couleur restant
/// stockee telle que choisie dans le picker, ces effets sont derives d'elle
/// a l'affichage plutot que stockes -- changer d'effet ne fait pas perdre la
/// couleur de base choisie.
enum SolidColorEffect { flat, gradient, pastel, metal, vibrant }

extension SolidColorEffectLabel on SolidColorEffect {
  String get label => switch (this) {
        SolidColorEffect.flat => 'Uni',
        SolidColorEffect.gradient => 'Degrade',
        SolidColorEffect.pastel => 'Pastel',
        SolidColorEffect.metal => 'Metal',
        SolidColorEffect.vibrant => 'Vibrant',
      };

  IconData get icon => switch (this) {
        SolidColorEffect.flat => Icons.square_rounded,
        SolidColorEffect.gradient => Icons.gradient_rounded,
        SolidColorEffect.pastel => Icons.filter_drama_rounded,
        SolidColorEffect.metal => Icons.auto_awesome_rounded,
        SolidColorEffect.vibrant => Icons.bolt_rounded,
      };
}

Color _lighten(Color base, double amount) {
  final hsl = HSLColor.fromColor(base);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

Color _darken(Color base, double amount) {
  final hsl = HSLColor.fromColor(base);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

Color pastelOf(Color base) {
  final hsl = HSLColor.fromColor(base);
  return hsl
      .withSaturation((hsl.saturation * 0.45).clamp(0.0, 1.0))
      .withLightness(
          (hsl.lightness + (1 - hsl.lightness) * 0.55).clamp(0.0, 1.0))
      .toColor();
}

/// Le reflet d'une surface metallique tire vers le blanc/gris (peu sature),
/// pas juste vers une version plus claire de la teinte de base -- une simple
/// eclaircie coloree est ce qui rendait le premier essai plus "plastique"
/// que "metal".
Color _specular(Color base) {
  final hsl = HSLColor.fromColor(base);
  return hsl
      .withSaturation((hsl.saturation * 0.25).clamp(0.0, 1.0))
      .withLightness(
          (hsl.lightness + (1 - hsl.lightness) * 0.85).clamp(0.0, 1.0))
      .toColor();
}

Color vibrantOf(Color base) {
  final hsl = HSLColor.fromColor(base);
  return hsl
      .withSaturation((hsl.saturation * 1.4 + 0.2).clamp(0.0, 1.0))
      .withLightness(hsl.lightness.clamp(0.32, 0.58))
      .toColor();
}

/// Fond en couleur unie avec l'effet choisi. Statefull uniquement pour porter
/// l'animation du mode "metal" (reflet qui balaie l'ecran en boucle) --
/// demarree/arretee a la volee dans didUpdateWidget quand l'effet change,
/// pour ne pas animer en continu quand ce n'est pas le mode actif.
class SolidEffectBackground extends StatefulWidget {
  final Color color;
  final SolidColorEffect effect;
  final Widget child;

  const SolidEffectBackground({
    super.key,
    required this.color,
    required this.effect,
    required this.child,
  });

  @override
  State<SolidEffectBackground> createState() => _SolidEffectBackgroundState();
}

class _SolidEffectBackgroundState extends State<SolidEffectBackground>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.effect == SolidColorEffect.metal) _startAnimating();
  }

  @override
  void didUpdateWidget(covariant SolidEffectBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    final needsAnimation = widget.effect == SolidColorEffect.metal;
    if (needsAnimation && _controller == null) {
      _startAnimating();
    } else if (!needsAnimation && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  void _startAnimating() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
      // Va-et-vient plutot qu'un cycle 0->1 qui saute -- un aller simple qui
      // recommence brusquement ressemble a un "shimmer" de chargement, pas a
      // un reflet ambiant.
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    switch (widget.effect) {
      case SolidColorEffect.flat:
        return ColoredBox(color: color, child: widget.child);

      case SolidColorEffect.gradient:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_lighten(color, 0.12), color, _darken(color, 0.18)],
            ),
          ),
          child: widget.child,
        );

      case SolidColorEffect.pastel:
        return ColoredBox(color: pastelOf(color), child: widget.child);

      case SolidColorEffect.vibrant:
        final vibrant = vibrantOf(color);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.3,
              colors: [_lighten(vibrant, 0.1), vibrant],
            ),
          ),
          child: widget.child,
        );

      case SolidColorEffect.metal:
        final curved =
            CurvedAnimation(parent: _controller!, curve: Curves.easeInOutSine);
        return AnimatedBuilder(
          animation: curved,
          builder: (context, _) {
            // Reflet etroit qui glisse en diagonale, va-et-vient doux plutot
            // qu'un balayage repetitif -- le tout sur une base legerement
            // assombrie sur les bords, comme une surface brossee.
            final sweep = curved.value * 1.3 - 0.15;
            final stops = [
              sweep - 0.12,
              sweep - 0.04,
              sweep,
              sweep + 0.04,
              sweep + 0.12,
            ].map((s) => s.clamp(0.0, 1.0)).toList();
            final base = _darken(color, 0.08);
            final specular = _specular(color);
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [base, base, specular, base, base],
                  stops: stops,
                ),
              ),
              child: widget.child,
            );
          },
        );
    }
  }
}
