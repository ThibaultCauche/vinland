import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'cover_image.dart';

/// Header (cover + titre + sous-titre) partage par toutes les feuilles
/// d'options "depuis le bas" (titre, album, playlist, artiste) -- evite de
/// dupliquer la meme mini-cover dans chaque ecran qui ouvre ce genre de menu.
class BottomSheetHeader extends StatelessWidget {
  final String? coverPath;
  final String title;
  final String subtitle;
  final IconData fallbackIcon;

  const BottomSheetHeader({
    super.key,
    required this.coverPath,
    required this.title,
    required this.subtitle,
    this.fallbackIcon = Icons.album,
  });

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final exists = context.read<AppState>().coverExists(coverPath);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: const Color(0xFF2A2A2A),
              image: exists && path != null
                  ? DecorationImage(
                      image: coverImageProvider(context,
                          path: path, width: 48, height: 48),
                      fit: BoxFit.cover,
                      onError: (_, __) {},
                    )
                  : null,
            ),
            child: !exists || coverPath == null
                ? Icon(fallbackIcon, color: Colors.white54, size: 24)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Une ligne d'action dans une feuille d'options "depuis le bas".
class SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  const SheetTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? Colors.white, size: 26),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
      minLeadingWidth: 24,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }
}

/// Feuille d'options "depuis le bas" partagee : scrollable et de hauteur
/// controlee (isScrollControlled) pour ne jamais deborder hors de l'ecran
/// quel que soit le nombre d'options -- voir le bug reel corrige sur celle
/// du big-player (options coupees, pas de scroll possible).
Future<T?> showOptionsSheet<T>(
  BuildContext context, {
  required List<Widget> Function(BuildContext sheetContext) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: builder(ctx),
        ),
      ),
    ),
  );
}
