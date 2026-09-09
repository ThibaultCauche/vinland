import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'glass.dart';

/// Fond d'ecran ambiant : la cover du titre en cours, tres floutee et
/// assombrie, derriere toute l'appli (comme le fond colore/flou de la
/// reference Behance). Sans lecture en cours, retombe sur un degrade fixe.
class DesktopBackground extends StatelessWidget {
  final Widget child;
  const DesktopBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, String?>(
      selector: (_, state) => state.currentTrack?.coverPath,
      builder: (context, coverPath, _) {
        final exists = context.read<AppState>().coverExists(coverPath);
        return Stack(
          fit: StackFit.expand,
          children: [
            Container(
                decoration:
                    const BoxDecoration(gradient: DesktopGlass.fallbackGradient)),
            if (exists && coverPath != null)
              Positioned.fill(
                child: Transform.scale(
                  scale: 1.25,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                    child: Image(
                      image: coverPath.startsWith('http')
                          ? NetworkImage(coverPath) as ImageProvider
                          : FileImage(File(coverPath)),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            Container(color: Colors.black.withOpacity(0.5)),
            child,
          ],
        );
      },
    );
  }
}
