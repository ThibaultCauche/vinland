import 'dart:ui';
import 'package:flutter/material.dart';

/// Design tokens partages par tout le shell desktop (verre depoli façon
/// Behance "Spotify Visual Ui / Vision Pro").
class DesktopGlass {
  static const accent = Color(0xFF1DB954);
  static const radiusLg = 24.0;
  static const radiusMd = 16.0;
  static const radiusSm = 10.0;

  /// Fond de reference quand aucun titre ne joue (pas de cover a flouter).
  static const fallbackGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF2B1B3D),
      Color(0xFF1B2A4A),
      Color(0xFF0E0E16),
    ],
  );
}

/// Panneau en verre depoli reutilisable : flou du fond + teinte translucide
/// + fine bordure claire, comme les cartes/sidebar/lecteur de la reference.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final Color tint;
  final Border? border;
  final EdgeInsetsGeometry? padding;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(DesktopGlass.radiusLg)),
    this.blurSigma = 30,
    this.tint = const Color(0x59000000),
    this.border,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: borderRadius,
            border: border ??
                Border.all(color: Colors.white.withOpacity(0.08), width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Bouton icone circulaire en verre, utilise dans la sidebar / la barre de
/// lecture (etat actif optionnel en surbrillance).
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
  final double size;
  final Color? color;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.size = 22,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Colors.white.withOpacity(0.14) : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: size,
            color: color ?? (active ? Colors.white : Colors.white70),
          ),
        ),
      ),
    );
  }
}

String formatPlayCount(int count) {
  final s = count.toString();
  final buffer = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
    buffer.write(s[i]);
  }
  return buffer.toString();
}

String formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
