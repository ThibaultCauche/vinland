import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/pinned_item.dart';
import '../models/playlist.dart';
import '../services/deep_link_service.dart';
import 'bottom_sheet_common.dart';

/// Feuille d'options d'une playlist (bouton "..." de sa page, liste de la
/// bibliotheque, ou clic long sur sa tuile) -- memes actions partout.
/// [onDeleted] : appele apres suppression, uniquement necessaire quand on est
/// affiche DANS la page de cette playlist (pour la quitter, elle n'existe
/// plus) -- ne rien passer depuis une liste/tuile, on y reste normalement.
void showPlaylistOptions(BuildContext context, Playlist playlist,
    {VoidCallback? onDeleted}) {
  final state = context.read<AppState>();

  showOptionsSheet(context, builder: (ctx) => [
    BottomSheetHeader(
      coverPath: null,
      title: playlist.name,
      subtitle: '${playlist.trackIds.length} titre(s)',
      fallbackIcon: Icons.queue_music,
    ),
    const Divider(color: Color(0xFF2A2A2A), height: 1),
    SheetTile(
      icon: state.isPinned(PinnedItemType.playlist, playlist.id)
          ? Icons.push_pin
          : Icons.push_pin_outlined,
      label: state.isPinned(PinnedItemType.playlist, playlist.id)
          ? "Desepingler de l'accueil"
          : "Epingler a l'accueil",
      onTap: () {
        Navigator.pop(ctx);
        state.togglePin(PinnedItem(
          type: PinnedItemType.playlist,
          id: playlist.id,
          title: playlist.name,
          subtitle: '${playlist.trackIds.length} titre(s)',
        ));
      },
    ),
    SheetTile(
      icon: playlist.isPublic ? Icons.public : Icons.public_off,
      label: playlist.isPublic
          ? 'Rendre privee'
          : 'Rendre publique (visible par les amis)',
      onTap: () {
        Navigator.pop(ctx);
        state.setPlaylistPublic(playlist.id, !playlist.isPublic);
      },
    ),
    SheetTile(
      icon: Icons.delete_outline,
      label: 'Supprimer la playlist',
      onTap: () {
        Navigator.pop(ctx);
        state.deletePlaylist(playlist.id);
        onDeleted?.call();
      },
    ),
    SheetTile(
      icon: Icons.ios_share,
      label: 'Partager',
      onTap: () {
        Navigator.pop(ctx);
        sharePlaylist(context, playlist);
      },
    ),
    if (state.shareInboxConfigured)
      SheetTile(
        icon: Icons.send_outlined,
        label: 'Envoyer a un ami',
        onTap: () {
          Navigator.pop(ctx);
          showSendToFriendDialog(context,
              type: 'playlist',
              title: playlist.name,
              subtitle: '${playlist.trackIds.length} titre(s)',
              playlistForPrivacyCheck: playlist);
        },
      ),
    const SizedBox(height: 8),
  ]);
}
