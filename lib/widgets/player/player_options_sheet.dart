import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../models/track.dart';
import '../../screens/album_screen.dart';
import '../../services/deep_link_service.dart';
import '../album_options_sheet.dart';
import '../artist_options_sheet.dart';
import '../bottom_sheet_common.dart';
import 'jam_controls.dart';

/// Popup ouverte en tapant le nom de l'artiste sur le big-player : deux
/// raccourcis rapides (artiste ou album du titre en cours) plutot que de
/// forcer un choix entre les deux destinations possibles (retour
/// utilisateur).
void showArtistAlbumPicker(BuildContext context, Track track) {
  final state = context.read<AppState>();
  showOptionsSheet(context, builder: (ctx) => [
    SheetTile(
      icon: Icons.person_outline,
      label: 'Artiste',
      onTap: () {
        Navigator.pop(ctx);
        showArtistPicker(context, track.artist);
      },
    ),
    SheetTile(
      icon: Icons.album_outlined,
      label: 'Album',
      onTap: () {
        Navigator.pop(ctx);
        state.pushOverlay(AlbumScreen(album: resolveTrackAlbum(state, track)));
      },
    ),
    const SizedBox(height: 8),
  ]);
}

void showPlayerOptions(BuildContext context, Track track) {
  final state = context.read<AppState>();

  showOptionsSheet(context, builder: (ctx) => [
    BottomSheetHeader(
      coverPath: track.coverPath,
      title: track.title,
      subtitle: track.artist,
    ),
    const Divider(color: Color(0xFF2A2A2A), height: 1),
    SheetTile(
      icon: Icons.add_circle_outline,
      label: 'Ajouter a la playlist',
      onTap: () {
        Navigator.pop(ctx);
        _showAddToPlaylistDialog(context, track);
      },
    ),
    SheetTile(
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
    SheetTile(
      icon: Icons.album_outlined,
      label: "Acceder a l'album",
      onTap: () {
        Navigator.pop(ctx);
        state.pushOverlay(AlbumScreen(album: resolveTrackAlbum(state, track)));
      },
    ),
    SheetTile(
      icon: Icons.person_outline,
      label: "Acceder a l'artiste",
      onTap: () {
        Navigator.pop(ctx);
        showArtistPicker(context, track.artist);
      },
    ),
    SheetTile(
      icon: Icons.ios_share,
      label: 'Partager',
      onTap: () {
        Navigator.pop(ctx);
        shareTrack(track);
      },
    ),
    if (state.shareInboxConfigured)
      SheetTile(
        icon: Icons.send_outlined,
        label: 'Envoyer a un ami',
        onTap: () {
          Navigator.pop(ctx);
          showSendToFriendDialog(context,
              type: 'track',
              itemId: track.id,
              title: track.title,
              subtitle: track.artist);
        },
      ),
    SheetTile(
      icon: state.isJamActive ? Icons.close : Icons.groups,
      label: state.isJamActive
          ? (state.isJamHost
              ? 'Session Jam (${state.jamParticipantCount} a l\'ecoute)'
              : 'Session Jam en cours')
          : 'Ecouter ensemble (Jam)',
      onTap: () {
        Navigator.pop(ctx);
        showJamMenu(context);
      },
    ),
    const SizedBox(height: 8),
  ]);
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
