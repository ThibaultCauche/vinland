import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../widgets/track_tile.dart';
import 'artist_screen.dart';
import 'album_screen.dart';
import '../models/album.dart';

class PlaylistScreen extends StatelessWidget {
  final Playlist playlist;

  const PlaylistScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, List<Track>>(
      selector: (_, state) {
        return state.allTracks
            .where((t) => playlist.trackIds.contains(t.id))
            .toList();
      },
      builder: (context, tracks, child) {
        final state = context.read<AppState>();

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => state.popOverlay(),
            ),
            title: Text(playlist.name,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () => _showPlaylistOptions(context, playlist),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.queue_music,
                          color: Colors.white54, size: 48),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playlist.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${playlist.trackIds.length} titre${playlist.trackIds.length > 1 ? 's' : ''}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: tracks.isNotEmpty
                          ? () =>
                              state.playTrack(tracks.first, trackList: tracks)
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Lecture'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1DB954),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.shuffle, color: Colors.white),
                      onPressed: tracks.isNotEmpty
                          ? () {
                              final shuffled = List.of(tracks)..shuffle();
                              state.playTrack(shuffled.first,
                                  trackList: shuffled);
                            }
                          : null,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: tracks.isEmpty
                    ? const Center(
                        child: Text('Aucun titre dans cette playlist',
                            style: TextStyle(color: Colors.white38)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 100),
                        itemCount: tracks.length,
                        itemBuilder: (context, i) => TrackTile(
                          track: tracks[i],
                          onTap: () =>
                              state.playTrack(tracks[i], trackList: tracks),
                          onLike: () => state.toggleLike(tracks[i].id),
                          onMore: () => _showTrackOptions(context, tracks[i]),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPlaylistOptions(BuildContext context, Playlist playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.queue_music,
                        color: Colors.white54, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playlist.name,
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
                          '${playlist.trackIds.length} titre(s)',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A2A2A), height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: Colors.white, size: 26),
              title: const Text('Supprimer la playlist',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                // TODO: ajouter deletePlaylist dans MusicService + AppState
              },
              minLeadingWidth: 24,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showTrackOptions(BuildContext context, Track track) {
    final state = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BottomSheetHeader(
              coverPath: track.coverPath,
              title: track.title,
              subtitle: track.artist,
            ),
            const Divider(color: Color(0xFF2A2A2A), height: 1),
            _SheetTile(
              icon: Icons.remove_circle_outline,
              label: 'Retirer de la playlist',
              onTap: () {
                Navigator.pop(ctx);
                state.musicService.removeFromPlaylist(playlist.id, track.id);
                state.notifyListeners();
              },
            ),
            _SheetTile(
              icon: track.isLiked ? Icons.favorite : Icons.favorite_border,
              label: track.isLiked
                  ? 'Retirer des titres likes'
                  : 'Ajouter aux titres likes',
              iconColor: track.isLiked ? const Color(0xFF1DB954) : Colors.white,
              onTap: () {
                Navigator.pop(ctx);
                state.toggleLike(track.id);
              },
            ),
            _SheetTile(
              icon: Icons.album_outlined,
              label: "Acceder a l'album",
              onTap: () {
                Navigator.pop(ctx);
                final album = state.likedAlbums.firstWhere(
                  (a) => a.title == track.album,
                  orElse: () => Album(
                    id: track.album.hashCode.toString(),
                    title: track.album,
                    artist: track.artist,
                    trackIds: [],
                  ),
                );
                state.pushOverlay(AlbumScreen(album: album));
              },
            ),
            _SheetTile(
              icon: Icons.person_outline,
              label: "Acceder a l'artiste",
              onTap: () {
                Navigator.pop(ctx);
                state.pushOverlay(ArtistScreen(artistName: track.artist));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _BottomSheetHeader extends StatelessWidget {
  final String? coverPath;
  final String title;
  final String subtitle;

  const _BottomSheetHeader({
    required this.coverPath,
    required this.title,
    required this.subtitle,
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
                      image: path.startsWith('http')
                          ? NetworkImage(path) as ImageProvider
                          : FileImage(File(path)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: !exists || coverPath == null
                ? const Icon(Icons.album, color: Colors.white54, size: 24)
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
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
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

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  const _SheetTile({
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
