import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/playlist.dart';
import 'glass.dart';

enum DesktopNavTab { home, search, library }

/// Rail d'icones a gauche : nav principale en haut, puis raccourcis
/// (titres likes + playlists) sous forme de vignettes carrees defilantes,
/// comme la colonne de gauche de la reference.
class DesktopSidebar extends StatelessWidget {
  final DesktopNavTab activeTab;
  final ValueChanged<DesktopNavTab> onTabSelected;
  final ValueChanged<Playlist> onOpenPlaylist;
  final VoidCallback onOpenLikedSongs;

  const DesktopSidebar({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
    required this.onOpenPlaylist,
    required this.onOpenLikedSongs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      margin: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      child: GlassPanel(
        borderRadius: BorderRadius.circular(DesktopGlass.radiusLg),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: DesktopGlass.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.graphic_eq, color: Colors.white, size: 18),
            ),
            const SizedBox(height: 20),
            GlassIconButton(
              icon: Icons.home_rounded,
              active: activeTab == DesktopNavTab.home,
              onPressed: () => onTabSelected(DesktopNavTab.home),
            ),
            const SizedBox(height: 6),
            GlassIconButton(
              icon: Icons.search_rounded,
              active: activeTab == DesktopNavTab.search,
              onPressed: () => onTabSelected(DesktopNavTab.search),
            ),
            const SizedBox(height: 6),
            GlassIconButton(
              icon: Icons.headphones_rounded,
              active: activeTab == DesktopNavTab.library,
              onPressed: () => onTabSelected(DesktopNavTab.library),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: Colors.white.withOpacity(0.12), height: 1),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Selector<AppState, List<Playlist>>(
                selector: (_, state) => state.playlists,
                builder: (context, playlists, __) {
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _LikedSongsShortcut(onTap: onOpenLikedSongs),
                      const SizedBox(height: 10),
                      for (final pl in playlists) ...[
                        _PlaylistShortcut(playlist: pl, onTap: () => onOpenPlaylist(pl)),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _LikedSongsShortcut extends StatelessWidget {
  final VoidCallback onTap;
  const _LikedSongsShortcut({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Titres likes',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7B5CFA), Color(0xFF3E2CA8)],
            ),
          ),
          child: const Icon(Icons.favorite, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _PlaylistShortcut extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  const _PlaylistShortcut({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final firstTrackCover = playlist.trackIds.isNotEmpty
        ? state.allTracks
            .where((t) => t.id == playlist.trackIds.first)
            .map((t) => t.coverPath)
            .firstOrNull
        : null;
    final exists = state.coverExists(firstTrackCover);

    return Tooltip(
      message: playlist.name,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF3E3E3E),
            borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
            image: exists && firstTrackCover != null
                ? DecorationImage(
                    image: firstTrackCover.startsWith('http')
                        ? NetworkImage(firstTrackCover) as ImageProvider
                        : FileImage(File(firstTrackCover)),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: !exists
              ? const Icon(Icons.queue_music, color: Colors.white54, size: 18)
              : null,
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
