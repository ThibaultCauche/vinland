import 'dart:ui';
import 'package:flutter/material.dart';

/// Design tokens partages par tout le shell desktop (verre depoli façon
/// Behance "Spotify Visual Ui / Vision Pro").
class DesktopGlass {
  static const accent = Color(0xFF1DB954);
  static const radiusLg = 24.0;
  static const radiusMd = 16.0;
  static const radiusSm = 10.0;

  /// Hauteur de la barre de titre custom (voir DesktopTitleBar) -- elle
  /// flotte desormais au-dessus de tout (sidebar + contenu), donc ce qui
  /// est dessous doit reserver cet espace pour ne pas demarrer derriere
  /// elle. Remontee de 36 a 48 (retour testeurs : la zone de
  /// glisser-deposer pour deplacer la fenetre etait trop fine pour etre
  /// attrapee confortablement).
  static const titleBarHeight = 48.0;

  /// Espace reserve en haut de chaque vue de contenu pour la barre de titre
  /// + la TopBar flottantes du shell (toutes deux sans fond opaque -- voir
  /// desktop_app_shell.dart) : le contenu qui defile passe dessous
  /// plutot que d'etre coupe net par une limite arbitraire au milieu de
  /// l'ecran, jusqu'au vrai bord haut de la fenetre.
  static const topInset = titleBarHeight + 8 + 44 + 12;

  /// Variante reduite de topInset, pour les vues poussees dans la pile
  /// locale (playlist/album/artiste) : leur propre en-tete pinned (hero qui
  /// se reduit) n'a pas besoin de la place reservee a la barre de recherche
  /// persistante (masquee sur ces vues, voir _TopBar.showSearchBar) -- ne
  /// garder que la place de la barre de titre custom, sinon un grand vide
  /// s'affichait entre elle et le bloc titre/cover (retour testeurs).
  static const topInsetCompact = titleBarHeight + 12;

  /// Espace reserve en bas de chaque vue de contenu pour la barre de
  /// lecture flottante du shell (hauteur 84 + sa propre marge de 12, voir
  /// DesktopPlayerBar) : meme principe que topInset, mais cote bas.
  static const playerBarReserve = 84.0 + 12.0;

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
    this.borderRadius =
        const BorderRadius.all(Radius.circular(DesktopGlass.radiusLg)),
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

/// Enrobe un element cliquable (cover d'un shelf, carte de resultat,
/// raccourci de la sidebar...) d'un curseur main au survol + une legere
/// surbrillance carree derriere l'element, comme les tuiles de la
/// reference Spotify -- contrairement a un GestureDetector nu, qui ne
/// montre jamais visuellement qu'il est cliquable. S'appuie sur
/// Material/InkWell plutot que de refaire cet etat de survol a la main :
/// le curseur main est deja automatique des que onTap est fourni.
class DesktopHoverable extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  const DesktopHoverable({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius =
        const BorderRadius.all(Radius.circular(DesktopGlass.radiusSm)),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        // Le curseur main par defaut d'InkWell ne se declenchait pas de
        // maniere fiable ici (verifie par l'utilisateur) -- on le force
        // explicitement plutot que de compter sur MaterialStateMouseCursor.
        mouseCursor: SystemMouseCursors.click,
        hoverColor: Colors.white.withOpacity(0.08),
        splashColor: Colors.white.withOpacity(0.06),
        highlightColor: Colors.white.withOpacity(0.04),
        child: child,
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
