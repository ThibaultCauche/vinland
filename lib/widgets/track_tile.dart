import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/app_state.dart';
import '../services/music_service.dart';
import 'cover_image.dart';
import 'like_heart_button.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback? onLike;
  final VoidCallback? onMore;
  final bool isPlaying;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.onLike,
    this.onMore,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    // Titre importe via CSV mais introuvable sur le NAS (voir
    // AppState.likedTracksWithMissing) : pas de fichier reel, donc grise et
    // non cliquable au lieu du rendu normal.
    if (track.isPlaceholder) {
      return ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF3E3E3E).withOpacity(0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(Icons.music_note, color: Colors.white24),
        ),
        title: Text(
          track.title,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${track.artist} • ${track.album}',
          style: const TextStyle(color: Colors.white24, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.error_outline,
            color: Colors.orange, size: 18),
      );
    }

    // FIX: utilise le cache mémoire de MusicService au lieu de File.exists()
    final coverExists =
        context.read<MusicService>().coverExists(track.coverPath);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: coverExists && track.coverPath != null
          ? Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                image: DecorationImage(
                  image: coverImageProvider(context,
                      path: track.coverPath!, width: 48, height: 48),
                  fit: BoxFit.cover,
                  onError: (_, __) {},
                ),
              ),
            )
          : Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF3E3E3E),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.music_note, color: Colors.white54),
            ),
      title: Text(
        track.title,
        style: TextStyle(
          color: isPlaying ? const Color(0xFF1DB954) : Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${track.artist} • ${track.album}',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onLike != null)
            LikeHeartButton(
              liked: track.isLiked,
              superLiked: track.superLiked,
              size: 20,
              onTap: onLike!,
              onLongPress: () =>
                  context.read<AppState>().toggleSuperLike(track.id),
            ),
          if (onMore != null)
            IconButton(
              icon:
                  const Icon(Icons.more_vert, color: Colors.white54, size: 20),
              onPressed: onMore,
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}
