import 'package:flutter/material.dart';
import '../widgets/artist_avatar.dart';
import 'desktop_home_view.dart';
import 'glass.dart';

/// Un element de la grille "Tout afficher" -- generique (titre/piste/album/
/// artiste) plutot que 3 widgets quasi-identiques, vu que seule la forme de
/// la cover (carree ou ronde) et l'action au tap changent d'une section a
/// l'autre.
class DesktopSeeAllItem {
  final String title;
  final String? subtitle;
  final String? coverPath;
  final bool circle;
  final VoidCallback onTap;

  const DesktopSeeAllItem({
    required this.title,
    this.subtitle,
    this.coverPath,
    this.circle = false,
    required this.onTap,
  });
}

/// Grille pleine page pour le bouton "Tout afficher" d'une section de
/// l'accueil (equivalent desktop de la page dediee de Spotify) : memes
/// elements que l'etagere horizontale d'origine, juste affiches en grille
/// plutot que dans une seule rangee qui defile.
class DesktopSeeAllView extends StatelessWidget {
  final String title;
  final List<DesktopSeeAllItem> items;

  const DesktopSeeAllView({
    super.key,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    // topInsetCompact : pas de barre de recherche persistante sur cette vue
    // poussee (voir DesktopCollectionView pour la meme raison).
    return Padding(
      padding: const EdgeInsets.only(
          top: DesktopGlass.topInsetCompact, left: 24, right: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.builder(
              padding:
                  const EdgeInsets.only(bottom: DesktopGlass.playerBarReserve),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 166,
                mainAxisExtent: 210,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                return DesktopHoverable(
                  onTap: item.onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        item.circle
                            // circle == true seulement pour les entrees
                            // artiste (voir DesktopHomeView._artistItems) --
                            // item.title y est deja le nom de l'artiste.
                            ? ArtistAvatar(
                                artistName: item.title,
                                fallbackCoverPath: item.coverPath,
                                size: 150,
                              )
                            : DesktopShelfCover(
                                coverPath: item.coverPath, size: 150),
                        const SizedBox(height: 8),
                        Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                        if (item.subtitle != null)
                          Text(item.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
