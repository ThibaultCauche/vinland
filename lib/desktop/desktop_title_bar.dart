import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/app_state.dart';
import '../services/update_check_service.dart';
import '../widgets/update_prompt.dart';
import 'glass.dart';

/// Remplace la barre de titre native Windows (reduire/agrandir/fermer) par
/// une version integree au design de l'app -- la fenetre est creee sans
/// bordure (main.dart, TitleBarStyle.hidden), donc sans ca il n'y aurait
/// plus aucun moyen de deplacer/reduire/fermer la fenetre.
class DesktopTitleBar extends StatefulWidget {
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onGoBack;
  final VoidCallback onGoForward;

  const DesktopTitleBar({
    super.key,
    required this.canGoBack,
    required this.canGoForward,
    required this.onGoBack,
    required this.onGoForward,
  });

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
          // Navigation avant/arriere façon navigateur, remplace le bouton
          // retour qui prenait sa propre ligne en haut de chaque page
          // poussee (album/artiste/playlist...) -- retour utilisateur.
          // Grises (onPressed null) quand inutilisables plutot que masques :
          // occuper toujours la meme largeur evite que le reste de la barre
          // ne saute d'un cote a l'autre au fil de la navigation.
          _TitleBarButton(
            icon: Icons.arrow_back_rounded,
            onPressed: widget.canGoBack ? widget.onGoBack : null,
          ),
          _TitleBarButton(
            icon: Icons.arrow_forward_rounded,
            onPressed: widget.canGoForward ? widget.onGoForward : null,
          ),
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
          Selector<AppState, UpdateInfo?>(
            selector: (_, state) => state.updateInfo,
            builder: (context, update, __) {
              if (update == null) return const SizedBox.shrink();
              return _TitleBarButton(
                icon: Icons.arrow_circle_down,
                color: const Color(0xFF1DB954),
                onPressed: () => triggerUpdate(context, update),
              );
            },
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
  // Nullable : un bouton grise (navigation avant/arriere indisponible)
  // occupe toujours sa place plutot que de disparaitre -- InkWell.onTap nul
  // desactive deja proprement le tap/hover/splash, pas besoin de gerer ca a
  // la main.
  final VoidCallback? onPressed;
  final Color? hoverColor;
  final Color? color;
  final double iconSize;

  const _TitleBarButton({
    required this.icon,
    required this.onPressed,
    this.hoverColor,
    this.color,
    this.iconSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return SizedBox(
      width: 46,
      height: DesktopGlass.titleBarHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          hoverColor: hoverColor ?? Colors.white.withOpacity(0.08),
          child: Icon(icon,
              size: iconSize,
              color: disabled ? Colors.white24 : (color ?? Colors.white70)),
        ),
      ),
    );
  }
}
