import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'player_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        if (state.currentTrack == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => state.pushOverlay(const PlayerScreen()),
          child: Container(
            height: 56,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Contenu principal
                Expanded(
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      _MiniCover(coverPath: state.currentTrack!.coverPath),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.currentTrack!.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              state.currentTrack!.artist,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          state.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => state.togglePlayPause(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next,
                            color: Colors.white, size: 28),
                        onPressed: () => state.nextTrack(),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                // Barre de progression fine (style Spotify)
                _MiniProgressBar(
                  position: state.position,
                  duration: state.duration,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MiniProgressBar extends StatelessWidget {
  final Duration position;
  final Duration duration;

  const _MiniProgressBar({required this.position, required this.duration});

  @override
  Widget build(BuildContext context) {
    final double progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Container(
      height: 2,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(1),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1DB954), // Vert Spotify
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}

class _MiniCover extends StatefulWidget {
  final String? coverPath;
  const _MiniCover({this.coverPath});

  @override
  State<_MiniCover> createState() => _MiniCoverState();
}

class _MiniCoverState extends State<_MiniCover> {
  bool? _exists;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant _MiniCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverPath != widget.coverPath) _check();
  }

  void _check() async {
    final path = widget.coverPath;
    if (path == null) {
      if (mounted) setState(() => _exists = false);
      return;
    }
    final result = await File(path).exists();
    if (mounted) setState(() => _exists = result);
  }

  @override
  Widget build(BuildContext context) {
    if (_exists == true) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          image: DecorationImage(
            image: FileImage(File(widget.coverPath!)),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF3E3E3E),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.music_note, color: Colors.white54, size: 20),
    );
  }
}
