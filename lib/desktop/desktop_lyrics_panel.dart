import 'package:flutter/material.dart';

import '../widgets/player/lyrics_view.dart';
import 'glass.dart';

/// Panneau des paroles a droite (PC), comme la file d'attente.
void showLyricsPanel(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Paroles',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => const _LyricsPanelOverlay(),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return Align(
        alignment: Alignment.centerRight,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _LyricsPanelOverlay extends StatelessWidget {
  const _LyricsPanelOverlay();

  @override
  Widget build(BuildContext context) {
    // Material : InkWell des lignes (voir desktop_queue_panel.dart).
    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 24, 24, 24 + 84 + 12),
          child: SizedBox(
            width: 420,
            child: GlassPanel(
              borderRadius: BorderRadius.circular(DesktopGlass.radiusLg),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Paroles',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        GlassIconButton(
                          icon: Icons.close,
                          size: 18,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const Expanded(child: LyricsView()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
