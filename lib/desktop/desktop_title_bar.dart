import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'glass.dart';

/// Remplace la barre de titre native Windows (reduire/agrandir/fermer) par
/// une version integree au design de l'app -- la fenetre est creee sans
/// bordure (main.dart, TitleBarStyle.hidden), donc sans ca il n'y aurait
/// plus aucun moyen de deplacer/reduire/fermer la fenetre.
class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({super.key});

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _isMaximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesktopGlass.titleBarHeight,
      child: Row(
        children: [
          // Plus de logo/texte ici : personne ne les lisait, et l'espace
          // sert desormais entierement de zone de glisser-deposer pour
          // deplacer la fenetre (double-tap = maximiser/restaurer), laissee
          // vide pour que la sidebar et la barre de recherche puissent
          // remonter juste en dessous (voir DesktopGlass.titleBarHeight).
          Expanded(
            child: DragToMoveArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () async {
                  if (await windowManager.isMaximized()) {
                    windowManager.unmaximize();
                  } else {
                    windowManager.maximize();
                  }
                },
              ),
            ),
          ),
          _TitleBarButton(
            icon: Icons.remove,
            onPressed: () => windowManager.minimize(),
          ),
          _TitleBarButton(
            icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
            iconSize: _isMaximized ? 14 : 16,
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                windowManager.unmaximize();
              } else {
                windowManager.maximize();
              }
            },
          ),
          _TitleBarButton(
            icon: Icons.close,
            hoverColor: const Color(0xFFE81123),
            onPressed: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _TitleBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? hoverColor;
  final double iconSize;

  const _TitleBarButton({
    required this.icon,
    required this.onPressed,
    this.hoverColor,
    this.iconSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: DesktopGlass.titleBarHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          hoverColor: hoverColor ?? Colors.white.withOpacity(0.08),
          child: Icon(icon, size: iconSize, color: Colors.white70),
        ),
      ),
    );
  }
}
