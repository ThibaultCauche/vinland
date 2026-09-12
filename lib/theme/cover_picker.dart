import 'package:flutter/material.dart';
import '../models/album.dart';
import '../widgets/cover_image.dart';

/// Bascule "Cover fixe" + apercu/bouton "Changer", utilisee dans les deux
/// sections de theme (mobile_theme_settings.dart, desktop_theme_settings.dart)
/// pour le mode "Cover floutee".
class PinnedCoverSection extends StatelessWidget {
  final String? pinnedCoverPath;
  final String? currentTrackCoverPath;
  final List<Album> albums;
  final ValueChanged<String?> onChanged;

  const PinnedCoverSection({
    super.key,
    required this.pinnedCoverPath,
    required this.currentTrackCoverPath,
    required this.albums,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pinned = pinnedCoverPath != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Cover fixe',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            Switch(
              value: pinned,
              activeColor: const Color(0xFF1DB954),
              onChanged: (v) {
                if (!v) {
                  onChanged(null);
                  return;
                }
                // Simple par defaut : fixer directement sur la cover du
                // titre en cours -- "Changer" en dessous permet d'en choisir
                // une autre depuis la bibliotheque si besoin.
                if (currentTrackCoverPath != null) {
                  onChanged(currentTrackCoverPath);
                } else {
                  pickAlbumCover(context, albums: albums).then((path) {
                    if (path != null) onChanged(path);
                  });
                }
              },
            ),
          ],
        ),
        if (pinned) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image(
                  image: coverImageProvider(context,
                      path: pinnedCoverPath!, width: 40, height: 40),
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => const SizedBox(
                      width: 40,
                      height: 40,
                      child: ColoredBox(color: Color(0xFF2A2A2A))),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () async {
                  final path = await pickAlbumCover(context, albums: albums);
                  if (path != null) onChanged(path);
                },
                child: const Text('Changer',
                    style: TextStyle(color: Color(0xFF1DB954))),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Choix d'une cover d'album a fixer comme fond (theme "Cover floutee") au
/// lieu de suivre le titre en cours de lecture -- partage entre les
/// Parametres > Personnalisation mobile et desktop. Retourne le coverPath
/// choisi, ou null si l'utilisateur annule.
Future<String?> pickAlbumCover(
  BuildContext context, {
  required List<Album> albums,
}) {
  final withCover = albums.where((a) => a.coverPath != null).toList();
  return showModalBottomSheet<String?>(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Choisir une cover',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: withCover.isEmpty
                  ? const Center(
                      child: Text('Aucune cover disponible',
                          style: TextStyle(color: Colors.white38)),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: withCover.length,
                      itemBuilder: (context, i) {
                        final album = withCover[i];
                        return GestureDetector(
                          onTap: () => Navigator.pop(context, album.coverPath),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image(
                              image: coverImageProvider(context,
                                  path: album.coverPath!,
                                  width: 120,
                                  height: 120),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) =>
                                  const ColoredBox(color: Color(0xFF2A2A2A)),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
