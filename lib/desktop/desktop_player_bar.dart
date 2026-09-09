import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import 'glass.dart';

/// Barre de lecture flottante en bas, en verre, avec transport centre et
/// volume/temps a droite -- calquee sur la reference Behance.
class DesktopPlayerBar extends StatelessWidget {
  const DesktopPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (Track?, bool)>(
      selector: (_, state) => (state.currentTrack, state.isPlaying),
      builder: (context, data, _) {
        final (track, isPlaying) = data;

        return Container(
          height: 84,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: GlassPanel(
            borderRadius: BorderRadius.circular(DesktopGlass.radiusLg),
            child: track == null
                ? const Center(
                    child: Text('Aucune lecture en cours',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                  )
                : Column(
                    children: [
                      const _SeekBar(),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 260,
                                child: _NowPlayingInfo(track: track),
                              ),
                              const Expanded(child: _TransportControls()),
                              const SizedBox(
                                width: 260,
                                child: _PlayerExtras(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar();

  @override
  Widget build(BuildContext context) {
    final player = context.read<AppState>().player;
    return StreamBuilder<Duration>(
      stream: Stream.periodic(
        const Duration(milliseconds: 200),
        (_) => player.position,
      ),
      builder: (context, snap) {
        final position = snap.data ?? Duration.zero;
        final duration = player.duration ?? Duration.zero;
        final progress = duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;

        return SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withOpacity(0.15),
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: progress.clamp(0.0, 1.0),
            onChanged: duration.inMilliseconds > 0
                ? (v) => context.read<AppState>().seek(
                      Duration(milliseconds: (v * duration.inMilliseconds).round()),
                    )
                : null,
          ),
        );
      },
    );
  }
}

class _NowPlayingInfo extends StatelessWidget {
  final Track track;
  const _NowPlayingInfo({required this.track});

  @override
  Widget build(BuildContext context) {
    final path = track.coverPath;
    final exists = context.read<AppState>().coverExists(path);

    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF3E3E3E),
            borderRadius: BorderRadius.circular(8),
            image: exists && path != null
                ? DecorationImage(
                    image: path.startsWith('http')
                        ? NetworkImage(path) as ImageProvider
                        : FileImage(File(path)),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: !exists ? const Icon(Icons.music_note, color: Colors.white54) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              Text(track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Selector<AppState, bool>(
          selector: (_, state) => state.isCurrentTrackLiked,
          builder: (context, isLiked, __) => GlassIconButton(
            icon: isLiked ? Icons.favorite : Icons.favorite_border,
            color: isLiked ? DesktopGlass.accent : Colors.white70,
            size: 18,
            onPressed: () => context.read<AppState>().toggleLike(track.id),
          ),
        ),
      ],
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls();

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (bool, LoopMode, bool)>(
      selector: (_, state) => (state.isShuffled, state.loopMode, state.isPlaying),
      builder: (context, data, __) {
        final (isShuffled, loopMode, isPlaying) = data;
        final state = context.read<AppState>();

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GlassIconButton(
              icon: Icons.shuffle,
              active: isShuffled,
              size: 18,
              onPressed: state.toggleShuffle,
            ),
            GlassIconButton(
              icon: Icons.skip_previous_rounded,
              size: 24,
              onPressed: state.previousTrack,
            ),
            const SizedBox(width: 4),
            Material(
              color: Colors.white,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: state.togglePlayPause,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.black,
                    size: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            GlassIconButton(
              icon: Icons.skip_next_rounded,
              size: 24,
              onPressed: state.nextTrack,
            ),
            GlassIconButton(
              icon: loopMode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
              active: loopMode != LoopMode.off,
              size: 18,
              onPressed: state.toggleLoopMode,
            ),
          ],
        );
      },
    );
  }
}

class _PlayerExtras extends StatefulWidget {
  const _PlayerExtras();

  @override
  State<_PlayerExtras> createState() => _PlayerExtrasState();
}

class _PlayerExtrasState extends State<_PlayerExtras> {
  double? _volume;

  @override
  Widget build(BuildContext context) {
    final player = context.read<AppState>().player;
    _volume ??= player.volume;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        StreamBuilder<Duration>(
          stream: Stream.periodic(
            const Duration(milliseconds: 500),
            (_) => player.position,
          ),
          builder: (context, snap) {
            final position = snap.data ?? Duration.zero;
            final duration = player.duration ?? Duration.zero;
            return Text(
              '${formatDuration(position)} / ${formatDuration(duration)}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            );
          },
        ),
        const SizedBox(width: 12),
        Icon(
          _volume! > 0.5
              ? Icons.volume_up_rounded
              : (_volume! > 0 ? Icons.volume_down_rounded : Icons.volume_off_rounded),
          color: Colors.white70,
          size: 18,
        ),
        SizedBox(
          width: 90,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withOpacity(0.15),
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: _volume!,
              onChanged: (v) {
                setState(() => _volume = v);
                player.setVolume(v);
              },
            ),
          ),
        ),
        GlassIconButton(
          icon: Icons.fullscreen_rounded,
          size: 18,
          onPressed: () {},
        ),
      ],
    );
  }
}
