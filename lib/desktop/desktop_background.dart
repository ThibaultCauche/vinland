import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/solid_color_effect.dart';
import '../widgets/cover_image.dart';
import 'desktop_theme.dart';

/// Fond de la fenetre desktop, selon le theme choisi dans Parametres > Apparence.
class DesktopBackground extends StatelessWidget {
  final Widget child;
  const DesktopBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (DesktopThemeMode, Color, SolidColorEffect)>(
      selector: (_, state) => (
        state.desktopThemeMode,
        state.desktopThemeColor,
        state.desktopSolidEffect,
      ),
      builder: (context, data, __) {
        final (mode, color, effect) = data;
        switch (mode) {
          case DesktopThemeMode.solid:
            return SolidEffectBackground(
                color: color, effect: effect, child: child);
          case DesktopThemeMode.coverBlur:
            return _CoverBlurBackground(child: child);
          case DesktopThemeMode.transparent:
            // La fenetre native est deja transparente (voir main.dart) : ce
            // flou/cette teinte s'ajoutent par-dessus pour rester lisibles.
            // Sur une machine ou le support natif fait defaut (voir
            // desktop_theme.dart), la fenetre reste opaque noire malgre tout.
            return Stack(
              fit: StackFit.expand,
              children: [
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(color: Colors.black.withValues(alpha: 0.25)),
                ),
                child,
              ],
            );
        }
      },
    );
  }
}

/// Rendu d'origine de l'app : la cover du titre en cours, tres floutee et
/// assombrie, derriere toute l'appli. Sans lecture en cours, degrade fixe.
class _CoverBlurBackground extends StatelessWidget {
  final Widget child;
  const _CoverBlurBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (String?, double, String?)>(
      selector: (_, state) => (
        state.currentTrack?.coverPath,
        state.desktopCoverBlurSigma,
        state.desktopPinnedCoverPath,
      ),
      builder: (context, data, _) {
        final (currentCoverPath, blurSigma, pinnedCoverPath) = data;
        final coverPath = pinnedCoverPath ?? currentCoverPath;
        final exists = context.read<AppState>().coverExists(coverPath);
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF2B1B3D),
                    Color(0xFF1B2A4A),
                    Color(0xFF0E0E16),
                  ],
                ),
              ),
            ),
            if (exists && coverPath != null)
              Positioned.fill(
                child: Transform.scale(
                  scale: 1.25,
                  child: ImageFiltered(
                    imageFilter:
                        ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                    // Flou tres fort applique dessus : aucun detail de la
                    // resolution native n'est de toute facon visible, donc
                    // decoder a une taille modeste suffit et evite de payer
                    // le decodage/upload GPU d'une cover en pleine resolution
                    // juste pour la flouter derriere toute l'appli.
                    child: Image(
                      image: coverImageProvider(context,
                          path: coverPath, width: 480, height: 480),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            Container(color: Colors.black.withValues(alpha: 0.5)),
            child,
          ],
        );
      },
    );
  }
}
