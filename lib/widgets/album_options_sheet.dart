import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/pinned_item.dart';
import '../models/track.dart';
import '../services/deep_link_service.dart';
import 'artist_options_sheet.dart';
import 'bottom_sheet_common.dart';

List<Track> tracksForAlbum(AppState state, Album album) {
  final ids = album.trackIds.toSet();
  return state.allTracks.where((t) => ids.contains(t.id)).toList()
    ..sort((a, b) => a.title.compareTo(b.title));
}

/// Resout l'Album REEL d'un titre -- match par albumId Navidrome (identifiant
/// reel, unique) quand il existe, plutot que par titre seul : deux albums
/// differents peuvent partager le meme titre (reedition, compilation...).
/// Meme logique que la resolution "Acceder a l'album" des feuilles d'options
/// titre ; utilisee ici par le big-player (nom d'artiste -> popup
/// Artiste/Album, titre -> ouvre l'album).
Album resolveTrackAlbum(AppState state, Track track) {
  final expectedId =
      track.albumId != null ? 'navidrome_${track.albumId}' : null;
  return state.albums.firstWhere(
    (a) => expectedId != null ? a.id == expectedId : a.title == track.album,
    orElse: () => Album(
      id: expectedId ?? track.album.hashCode.toString(),
      title: track.album,
      artist: track.albumArtist ?? track.artist,
      trackIds: state.allTracks
          .where((t) => expectedId != null
              ? t.albumId == track.albumId
              : t.album == track.album)
          .map((t) => t.id)
          .toList(),
      coverPath: track.coverPath,
    ),
  );
}

/// Feuille d'options d'un album (bouton "..." de sa page, ou clic long sur
/// sa tuile) -- memes actions partout.
void showAlbumOptions(BuildContext context, Album album) {
  final state = context.read<AppState>();
  final tracks = tracksForAlbum(state, album);

  showOptionsSheet(context, builder: (ctx) => [
    BottomSheetHeader(
      coverPath: album.coverPath,
      title: album.title,
      subtitle: album.artist,
    ),
    const Divider(color: Color(0xFF2A2A2A), height: 1),
    SheetTile(
      icon: album.isSaved ? Icons.favorite : Icons.favorite_border,
      label: album.isSaved ? 'Retirer des albums likes' : 'Ajouter aux albums likes',
      iconColor: album.isSaved ? const Color(0xFF1DB954) : Colors.white,
      onTap: () {
        Navigator.pop(ctx);
        state.toggleLikeAlbum(album.id);
      },
    ),
    SheetTile(
      icon: Icons.person_outline,
      label: "Acceder a l'artiste",
      onTap: () {
        Navigator.pop(ctx);
        showArtistPicker(context, album.artist);
      },
    ),
    SheetTile(
      icon: state.isPinned(PinnedItemType.album, album.id)
          ? Icons.push_pin
          : Icons.push_pin_outlined,
      label: state.isPinned(PinnedItemType.album, album.id)
          ? "Desepingler de l'accueil"
          : "Epingler a l'accueil",
      onTap: () {
        Navigator.pop(ctx);
        state.togglePin(PinnedItem(
          type: PinnedItemType.album,
          id: album.id,
          title: album.title,
          subtitle: album.artist,
        ));
      },
    ),
    SheetTile(
      icon: Icons.playlist_play,
      label: 'Lire ensuite',
      onTap: () {
        Navigator.pop(ctx);
        for (final t in tracks.reversed) {
          state.playNext(t);
        }
      },
    ),
    SheetTile(
      icon: Icons.playlist_add,
      label: "Ajouter a la file d'attente",
      onTap: () {
        Navigator.pop(ctx);
        for (final t in tracks) {
          state.addToQueue(t);
        }
      },
    ),
    SheetTile(
      icon: Icons.ios_share,
      label: 'Partager',
      onTap: () {
        Navigator.pop(ctx);
        shareAlbum(album);
      },
    ),
    if (state.shareInboxConfigured)
      SheetTile(
        icon: Icons.send_outlined,
        label: 'Envoyer a un ami',
        onTap: () {
          Navigator.pop(ctx);
          showSendToFriendDialog(context,
              type: 'album',
              itemId: album.id,
              title: album.title,
              subtitle: album.artist);
        },
      ),
    const SizedBox(height: 8),
  ]);
}
