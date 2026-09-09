import 'dart:io';
import 'package:flutter/material.dart';
import '../models/track.dart';
import 'glass.dart';

/// Ligne de titre façon reference : cover, titre/artiste, ecoutes, duree,
/// like puis menu, avec un survol legerement eclairci.
class DesktopTrackRow extends StatefulWidget {
  final Track track;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onMore;

  const DesktopTrackRow({
    super.key,
    required this.track,
    required this.onTap,
    required this.onLike,
    required this.onMore,
    this.isPlaying = false,
  });

  @override
  State<DesktopTrackRow> createState() => _DesktopTrackRowState();
}

class _DesktopTrackRowState extends State<DesktopTrackRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final path = track.coverPath;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: _hover ? Colors.white.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF3E3E3E),
                  borderRadius: BorderRadius.circular(6),
                  image: path != null
                      ? DecorationImage(
                          image: path.startsWith('http')
                              ? NetworkImage(path) as ImageProvider
                              : FileImage(File(path)),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: path == null
                    ? const Icon(Icons.music_note, color: Colors.white54, size: 18)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.isPlaying ? DesktopGlass.accent : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  formatPlayCount(track.playCount),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  formatDuration(track.duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              GlassIconButton(
                icon: track.isLiked ? Icons.favorite : Icons.favorite_border,
                color: track.isLiked ? DesktopGlass.accent : Colors.white54,
                size: 18,
                onPressed: widget.onLike,
              ),
              GlassIconButton(
                icon: Icons.more_horiz,
                color: Colors.white54,
                size: 18,
                onPressed: widget.onMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
