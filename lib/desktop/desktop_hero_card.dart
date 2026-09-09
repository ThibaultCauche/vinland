import 'dart:io';
import 'package:flutter/material.dart';
import 'glass.dart';

/// Grande carte d'en-tete d'une playlist/album/artiste : cover en fond a
/// droite, degrade sombre a gauche pour la lisibilite du texte, titre,
/// sous-titre, compteur et bouton "Lecture aleatoire" -- comme la reference.
class DesktopHeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String metaLabel;
  final String? coverPath;
  final bool isLiked;
  final VoidCallback? onToggleLike;
  final VoidCallback onShuffle;

  const DesktopHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.metaLabel,
    required this.coverPath,
    required this.onShuffle,
    this.isLiked = false,
    this.onToggleLike,
  });

  @override
  Widget build(BuildContext context) {
    final path = coverPath;

    return SizedBox(
      height: 220,
      child: GlassPanel(
        borderRadius: BorderRadius.circular(DesktopGlass.radiusLg),
        tint: Colors.transparent,
        blurSigma: 0,
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (path != null)
              Image(
                image: path.startsWith('http')
                    ? NetworkImage(path) as ImageProvider
                    : FileImage(File(path)),
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
              )
            else
              const DecoratedBox(decoration: BoxDecoration(color: Color(0xFF2A2A2A))),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withOpacity(0.75),
                    Colors.black.withOpacity(0.55),
                    Colors.black.withOpacity(0.05),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 420,
                    child: Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      if (onToggleLike != null)
                        GestureDetector(
                          onTap: onToggleLike,
                          child: Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            color: isLiked ? DesktopGlass.accent : Colors.white,
                            size: 20,
                          ),
                        ),
                      if (onToggleLike != null) const SizedBox(width: 8),
                      Text(metaLabel,
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(width: 20),
                      Material(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: onShuffle,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Lecture aleatoire',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                SizedBox(width: 8),
                                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
