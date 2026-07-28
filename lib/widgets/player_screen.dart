import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        final track = state.currentTrack;
        if (track == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF121212),
            body: Center(
              child: Text('Aucune lecture',
                  style: TextStyle(color: Colors.white38)),
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: SafeArea(
            child: Column(
              children: [
                // Header avec padding top pour éviter la barre de notif
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Cover
                Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.music_note,
                      color: Colors.white54, size: 80),
                ),

                const Spacer(),

                // Info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              track.artist,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          track.isLiked
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: track.isLiked
                              ? const Color(0xFF1DB954)
                              : Colors.white,
                          size: 28,
                        ),
                        onPressed: () => state.toggleLike(track.id),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Progress bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Slider(
                        value: state.position.inMilliseconds.toDouble().clamp(
                              0,
                              state.duration.inMilliseconds.toDouble().max(1),
                            ),
                        max: state.duration.inMilliseconds.toDouble().max(1),
                        activeColor: Colors.white,
                        inactiveColor: Colors.white24,
                        onChanged: (v) =>
                            state.seek(Duration(milliseconds: v.toInt())),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatTime(state.position),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                          Text(
                            _formatTime(state.duration),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Controls
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shuffle, color: Colors.white54),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous,
                            color: Colors.white, size: 36),
                        onPressed: () => state.previousTrack(),
                      ),
                      GestureDetector(
                        onTap: () => state.togglePlayPause(),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            state.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.black,
                            size: 36,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next,
                            color: Colors.white, size: 36),
                        onPressed: () => state.nextTrack(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.repeat, color: Colors.white54),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

extension on double {
  double max(double other) => this > other ? this : other;
}
