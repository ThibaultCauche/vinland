import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../services/music_service.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback? onLike;
  final VoidCallback? onMore;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.onLike,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
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
                  image: track.coverPath!.startsWith('http')
                      ? NetworkImage(track.coverPath!) as ImageProvider
                      : FileImage(File(track.coverPath!)),
                  fit: BoxFit.cover,
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
        style: const TextStyle(
          color: Colors.white,
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
            IconButton(
              icon: Icon(
                track.isLiked ? Icons.favorite : Icons.favorite_border,
                color: track.isLiked ? const Color(0xFF1DB954) : Colors.white54,
                size: 20,
              ),
              onPressed: onLike,
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
