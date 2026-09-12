import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import 'player_screen.dart';
import 'cover_image.dart';
import 'like_heart_button.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (Track?, Color?, bool, bool)>(
      selector: (_, state) => (
        state.currentTrack,
        state.dominantColor,
        state.isPlaying,
        state.isJamActive
      ),
      builder: (context, data, child) {
        final (track, dominantColor, isPlaying, isJamActive) = data;
        if (track == null) {
          return const SizedBox(height: 64);
        }

        return GestureDetector(
          onTap: () =>
              context.read<AppState>().pushOverlay(const PlayerScreen()),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  dominantColor != null
                      ? Color.lerp(dominantColor, const Color(0xFF1E1E1E), 0.5)!
                      : const Color(0xFF1E1E1E),
                  const Color(0xFF1E1E1E),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      _MiniCover(coverPath: track.coverPath),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (isJamActive)
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1DB954),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'JAM',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    track.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              track.artist,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      _LikeButton(trackId: track.id),
                      IconButton(
                        icon: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () =>
                            context.read<AppState>().togglePlayPause(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next,
                            color: Colors.white, size: 28),
                        onPressed: () => context.read<AppState>().nextTrack(),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                RepaintBoundary(child: _MiniProgressBar(track: track)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LikeButton extends StatelessWidget {
  final String trackId;
  const _LikeButton({required this.trackId});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (bool, bool)>(
      selector: (_, state) =>
          (state.isCurrentTrackLiked, state.isCurrentTrackSuperLiked),
      builder: (context, data, _) {
        final (isLiked, isSuperLiked) = data;
        return LikeHeartButton(
          liked: isLiked,
          superLiked: isSuperLiked,
          size: 22,
          idleColor: Colors.white,
          onTap: () => context.read<AppState>().toggleLike(trackId),
          onLongPress: () =>
              context.read<AppState>().toggleSuperLike(trackId),
        );
      },
    );
  }
}

class _MiniProgressBar extends StatelessWidget {
  final Track track;
  const _MiniProgressBar({required this.track});

  @override
  Widget build(BuildContext context) {
    final player = context.read<AppState>().player;
    return StreamBuilder<Duration>(
      // 200ms = 5 mises à jour/seconde max (suffisant visuellement)
      stream: Stream.periodic(
        const Duration(milliseconds: 200),
        (_) => player.position,
      ),
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        // La duree connue via les metadonnees NAS (fiable) est preferee a
        // celle remontee en direct par le moteur de lecture : sur
        // Windows/Linux (media_kit/libmpv), un flux transcode par Navidrome
        // sans Content-Length force libmpv a re-estimer la duree au fur et
        // a mesure du telechargement (elle grimpe par paliers de ~10s), ce
        // qui faisait sauter la barre de progression pendant les premieres
        // secondes de lecture.
        final duration = track.duration.inMilliseconds > 0
            ? track.duration
            : (player.duration ?? Duration.zero);
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
                color: const Color(0xFF1DB954),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniCover extends StatelessWidget {
  final String? coverPath;
  const _MiniCover({this.coverPath});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final exists = context.read<AppState>().coverExists(coverPath);

    if (exists && path != null) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          image: DecorationImage(
            image:
                coverImageProvider(context, path: path, width: 40, height: 40),
            fit: BoxFit.cover,
            onError: (_, __) {},
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
