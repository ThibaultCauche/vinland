import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../providers/app_state.dart';
import 'cover_image.dart';

/// Cover d'une playlist -- Navidrome ne permet pas d'en stocker une dediee,
/// donc on compose un collage 2x2 avec les covers de ses propres titres
/// (comme Spotify), plutot que la meme icone generique partout (retour
/// utilisateur : "les playlists n'ont pas de cover"). Se rabat sur 1 seule
/// cover en plein cadre si moins de 4 titres ont une cover exploitable, puis
/// sur l'icone generique si aucun.
class PlaylistCover extends StatelessWidget {
  final Playlist playlist;
  final double size;
  final BorderRadius borderRadius;

  PlaylistCover({
    super.key,
    required this.playlist,
    required this.size,
    BorderRadius? borderRadius,
  }) : borderRadius = borderRadius ?? BorderRadius.circular(4);

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final tracksById = {for (final t in state.allTracks) t.id: t};

    final covers = <String>[];
    for (final id in playlist.trackIds) {
      if (covers.length >= 4) break;
      final path = tracksById[id]?.coverPath;
      if (path != null && !covers.contains(path) && state.coverExists(path)) {
        covers.add(path);
      }
    }

    if (covers.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: borderRadius,
        ),
        child: Icon(Icons.queue_music, color: Colors.white54, size: size * 0.45),
      );
    }

    if (covers.length < 4) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: _tile(context, covers.first, size),
      );
    }

    final half = size / 2;
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              _tile(context, covers[0], half),
              _tile(context, covers[1], half),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _tile(context, covers[2], half),
              _tile(context, covers[3], half),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, String path, double s) => Image(
        image: coverImageProvider(context, path: path, width: s, height: s),
        width: s,
        height: s,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Container(width: s, height: s, color: const Color(0xFF2A2A2A)),
      );
}
