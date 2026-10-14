import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/smart_playlists.dart';
import '../providers/app_state.dart';
import '../screens/playlist_screen.dart';
import 'playlist_cover.dart';

/// Rangee « Playlists intelligentes » de l'accueil mobile. Rien du tout si
/// la bibliotheque n'en donne aucune (pas assez de titres).
class SmartPlaylistShelf extends StatelessWidget {
  const SmartPlaylistShelf({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, List<SmartPlaylist>>(
      selector: (_, state) => state.smartPlaylists,
      builder: (context, playlists, _) {
        if (playlists.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text('Playlists intelligentes',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              height: 190,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: playlists.length,
                itemBuilder: (context, i) =>
                    _SmartPlaylistTile(smart: playlists[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SmartPlaylistTile extends StatelessWidget {
  const _SmartPlaylistTile({required this.smart});

  final SmartPlaylist smart;

  @override
  Widget build(BuildContext context) {
    final playlist = smart.toPlaylist();
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 130,
        child: GestureDetector(
          onTap: () => context
              .read<AppState>()
              .pushOverlay(PlaylistScreen(playlist: playlist, smart: true)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PlaylistCover(
                playlist: playlist,
                size: 130,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 8),
              Text(smart.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              Text(smart.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
