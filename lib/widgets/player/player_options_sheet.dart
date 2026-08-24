import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../models/track.dart';
import '../../models/album.dart';
import '../../screens/artist_screen.dart';
import '../../screens/album_screen.dart';

void showPlayerOptions(BuildContext context, Track track) {
  final state = context.read<AppState>();
  final coverExists = state.coverExists(track.coverPath);

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
          _SheetHeader(track: track, coverExists: coverExists),
          const Divider(color: Color(0xFF2A2A2A), height: 1),
          _SheetTile(
            icon: Icons.add_circle_outline,
            label: 'Ajouter a la playlist',
            onTap: () {
              Navigator.pop(ctx);
              _showAddToPlaylistDialog(context, track);
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
              final album = state.albums.firstWhere(
                (a) => a.title == track.album,
                orElse: () => Album(
                  id: track.album.hashCode.toString(),
                  title: track.album,
                  artist: track.albumArtist ?? track.artist,
                  trackIds: state.allTracks
                      .where((t) => t.album == track.album)
                      .map((t) => t.id)
                      .toList(),
                  coverPath: track.coverPath,
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
              _showArtistPicker(context, track.artist);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void _showArtistPicker(BuildContext context, String artistsField) {
  final artists = artistsField
      .split(RegExp(r'[/&,]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  if (artists.length <= 1) {
    context
        .read<AppState>()
        .pushOverlay(ArtistScreen(artistName: artistsField));
    return;
  }

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
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Selectionner un artiste',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(color: Color(0xFF2A2A2A), height: 1),
          ...artists.map((artist) => ListTile(
                leading: const Icon(Icons.person, color: Colors.white),
                title:
                    Text(artist, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  context
                      .read<AppState>()
                      .pushOverlay(ArtistScreen(artistName: artist));
                },
              )),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void _showAddToPlaylistDialog(BuildContext context, Track track) {
  final state = context.read<AppState>();
  final playlists = state.playlists;

  if (playlists.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Aucune playlist. Creez-en une d'abord."),
        backgroundColor: Color(0xFF2A2A2A),
      ),
    );
    return;
  }

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Ajouter a une playlist',
          style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: playlists.length,
          itemBuilder: (_, i) => ListTile(
            title: Text(playlists[i].name,
                style: const TextStyle(color: Colors.white)),
            onTap: () {
              state.addToPlaylist(playlists[i].id, track.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Ajoute a ${playlists[i].name}'),
                  backgroundColor: const Color(0xFF2A2A2A),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
        ),
      ],
    ),
  );
}

class _SheetHeader extends StatelessWidget {
  final Track track;
  final bool coverExists;
  const _SheetHeader({required this.track, required this.coverExists});

  @override
  Widget build(BuildContext context) {
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
              image: coverExists && track.coverPath != null
                  ? DecorationImage(
                      image: track.coverPath!.startsWith('http')
                          ? NetworkImage(track.coverPath!) as ImageProvider
                          : FileImage(File(track.coverPath!)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: !coverExists || track.coverPath == null
                ? const Icon(Icons.album, color: Colors.white54, size: 24)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
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
                  track.artist,
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
