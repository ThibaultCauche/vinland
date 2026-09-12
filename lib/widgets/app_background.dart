import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../desktop/desktop_background.dart';
import '../providers/app_state.dart';
import '../theme/mobile_theme.dart';
import '../theme/solid_color_effect.dart';
import 'cover_image.dart';

/// Fond pour un ecran partage entre mobile et desktop (Parametres,
/// Feedback, Import streaming...) : ces ecrans sont pousses en overlay
/// (deja dans AppBackground) sur mobile, mais en vraie route Navigator.push
/// sur desktop -- la ou rien ne garantit que DesktopBackground soit derriere.
/// Choisit donc le bon fond explicitement selon la plateforme au lieu de
/// supposer lequel des deux shells a pousse l'ecran.
class PlatformBackground extends StatelessWidget {
  final Widget child;
  const PlatformBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return DesktopBackground(child: child);
    }
    return AppBackground(child: child);
  }
}

/// Fond commun a tous les ecrans mobile, selon le theme choisi dans
/// Parametres > Personnalisation. Equivalent mobile de DesktopBackground
/// (lib/desktop/desktop_background.dart), branche une seule fois autour du
/// Stack de _MobileAppShell (voir main.dart) : les ecrans individuels
/// (HomeScreen, LibraryScreen, ...) doivent alors garder un Scaffold
/// transparent pour laisser ce fond transparaitre.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (MobileThemeMode, Color, SolidColorEffect)>(
      selector: (_, state) => (
        state.mobileThemeMode,
        state.mobileThemeColor,
        state.mobileSolidEffect,
      ),
      builder: (context, data, __) {
        final (mode, color, effect) = data;
        switch (mode) {
          case MobileThemeMode.solid:
            return SolidEffectBackground(
                color: color, effect: effect, child: child);
          case MobileThemeMode.coverBlur:
            return _CoverBlurBackground(child: child);
        }
      },
    );
  }
}

class _CoverBlurBackground extends StatelessWidget {
  final Widget child;
  const _CoverBlurBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (String?, double, String?)>(
      selector: (_, state) => (
        state.currentTrack?.coverPath,
        state.mobileCoverBlurSigma,
        state.mobilePinnedCoverPath,
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
