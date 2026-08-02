import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../services/music_service.dart';
import '../services/audio_handler.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (Track?, Color?)>(
      selector: (_, state) => (state.currentTrack, state.dominantColor),
      builder: (context, data, child) {
        final (track, dominantColor) = data;
        if (track == null) return const SizedBox.shrink();

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: dominantColor != null
                ? Color.lerp(dominantColor, Colors.black, 0.4)
                : const Color(0xFF121212),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.expand_more, color: Colors.white),
              onPressed: () => context.read<AppState>().popOverlay(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () {},
              ),
            ],
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  dominantColor != null
                      ? Color.lerp(dominantColor, Colors.black, 0.4)!
                      : const Color(0xFF121212),
                  const Color(0xFF121212),
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    _PlayerCover(coverPath: track.coverPath),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                track.artist,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        _LikeButton(trackId: track.id),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _PlayerSlider(),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.shuffle,
                              color: Colors.white54, size: 28),
                          onPressed: () {},
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_previous,
                              color: Colors.white, size: 36),
                          onPressed: () =>
                              context.read<AppState>().previousTrack(),
                        ),
                        _PlayPauseButton(),
                        IconButton(
                          icon: const Icon(Icons.skip_next,
                              color: Colors.white, size: 36),
                          onPressed: () => context.read<AppState>().nextTrack(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.repeat,
                              color: Colors.white54, size: 28),
                          onPressed: () {},
                        ),
                      ],
                    ),
                    const Spacer(),
                  ],
                ),
              ),
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
    return Selector<AppState, bool>(
      selector: (_, state) => state.isCurrentTrackLiked,
      builder: (context, isLiked, _) => IconButton(
        icon: Icon(
          isLiked ? Icons.favorite : Icons.favorite_border,
          color: isLiked ? const Color(0xFF1DB954) : Colors.white,
        ),
        onPressed: () => context.read<AppState>().toggleLike(trackId),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Selector<AppState, bool>(
      selector: (_, state) => state.isPlaying,
      builder: (context, isPlaying, _) => Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.black,
            size: 32,
          ),
          onPressed: () => context.read<AppState>().togglePlayPause(),
        ),
      ),
    );
  }
}

class _PlayerSlider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final player = context.read<VinlandAudioHandler>().player;
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, posSnap) {
        return StreamBuilder<Duration?>(
          stream: player.durationStream,
          builder: (context, durSnap) {
            final position = posSnap.data ?? Duration.zero;
            final duration = durSnap.data ?? Duration.zero;
            final max =
                duration.inSeconds.toDouble().clamp(1, 99999).toDouble();

            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value:
                        position.inSeconds.toDouble().clamp(0, max).toDouble(),
                    max: max,
                    onChanged: (value) {
                      context
                          .read<AppState>()
                          .seek(Duration(seconds: value.toInt()));
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(position),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    Text(
                      _formatDuration(duration),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _PlayerCover extends StatelessWidget {
  final String? coverPath;
  const _PlayerCover({this.coverPath});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final exists = context.read<MusicService>().coverExists(coverPath);

    if (exists && path != null) {
      return Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.width - 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          image: DecorationImage(
            image: FileImage(File(path)),
            fit: BoxFit.cover,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      height: MediaQuery.of(context).size.width - 48,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.album, color: Colors.white54, size: 100),
    );
  }
}
