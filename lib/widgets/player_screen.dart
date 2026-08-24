import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import 'player/like_button.dart';
import 'player/play_pause_button.dart';
import 'player/player_slider.dart';
import 'player/player_cover.dart';
import 'player/player_options_sheet.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (Track?, Color?, bool, LoopMode)>(
      selector: (_, state) => (
        state.currentTrack,
        state.dominantColor,
        state.isShuffled,
        state.loopMode,
      ),
      builder: (context, data, child) {
        final (track, dominantColor, isShuffled, loopMode) = data;
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
                onPressed: () => showPlayerOptions(context, track),
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
                    PlayerCover(coverPath: track.coverPath),
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
                        PlayerLikeButton(trackId: track.id),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const PlayerSlider(),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.shuffle,
                            color: isShuffled
                                ? const Color(0xFF1DB954)
                                : Colors.white54,
                            size: 28,
                          ),
                          onPressed: () =>
                              context.read<AppState>().toggleShuffle(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_previous,
                              color: Colors.white, size: 36),
                          onPressed: () =>
                              context.read<AppState>().previousTrack(),
                        ),
                        const PlayPauseButton(),
                        IconButton(
                          icon: const Icon(Icons.skip_next,
                              color: Colors.white, size: 36),
                          onPressed: () => context.read<AppState>().nextTrack(),
                        ),
                        IconButton(
                          icon: Icon(
                            loopMode == LoopMode.one
                                ? Icons.repeat_one
                                : Icons.repeat,
                            color: loopMode != LoopMode.off
                                ? const Color(0xFF1DB954)
                                : Colors.white54,
                            size: 28,
                          ),
                          onPressed: () =>
                              context.read<AppState>().toggleLoopMode(),
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
