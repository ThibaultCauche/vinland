import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/track.dart';
import '../widgets/cover_image.dart';
import '../widgets/player/jam_controls.dart';
import 'desktop_queue_panel.dart';
import 'glass.dart';

/// Barre de lecture flottante en bas, en verre, avec transport centre et
/// volume/temps a droite -- calquee sur la reference Behance.
class DesktopPlayerBar extends StatelessWidget {
  final void Function(Album album) onOpenAlbum;
  final void Function(String artistName) onOpenArtist;

  const DesktopPlayerBar({
    super.key,
    required this.onOpenAlbum,
    required this.onOpenArtist,
  });

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
                      // RepaintBoundary : le slider/le texte position-duree
                      // ci-dessous se re-peignent 2 a 5x/seconde pendant la
                      // lecture (StreamBuilder). Sans frontiere de repaint
                      // ici, chaque tick forcerait le flou en verre depoli
                      // (BackdropFilter) de ce GlassPanel a se recalculer en
                      // entier au meme rythme -- couteux pour un gain visuel
                      // nul, le flou lui-meme ne changeant jamais.
                      RepaintBoundary(child: _SeekBar(track: track)),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 260,
                                child: _NowPlayingInfo(
                                  track: track,
                                  onOpenAlbum: onOpenAlbum,
                                  onOpenArtist: onOpenArtist,
                                ),
                              ),
                              const Expanded(child: _TransportControls()),
                              SizedBox(
                                width: 260,
                                child: RepaintBoundary(
                                    child: _PlayerExtras(track: track)),
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
  final Track track;
  const _SeekBar({required this.track});

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
        // Duree metadonnees NAS preferee a celle du moteur (media_kit
        // grimpe par paliers en debut de lecture sur un flux Navidrome sans
        // Content-Length) -- voir mini_player.dart pour le detail.
        final duration = track.duration.inMilliseconds > 0
            ? track.duration
            : (player.duration ?? Duration.zero);
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
                      Duration(
                          milliseconds: (v * duration.inMilliseconds).round()),
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
  final void Function(Album album) onOpenAlbum;
  final void Function(String artistName) onOpenArtist;

  const _NowPlayingInfo({
    required this.track,
    required this.onOpenAlbum,
    required this.onOpenArtist,
  });

  /// Retrouve l'album local du titre via trackIds (fiable, pas de
  /// correspondance approximative sur le nom).
  Album? _findAlbum(AppState state) {
    for (final a in state.albums) {
      if (a.trackIds.contains(track.id)) return a;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final path = track.coverPath;
    final state = context.read<AppState>();
    final exists = state.coverExists(path);
    final album = _findAlbum(state);
    final artistNames = track.artist
        .split(RegExp(r'[/&,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

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
                    image: coverImageProvider(context,
                        path: path, width: 52, height: 52),
                    fit: BoxFit.cover,
                    onError: (_, __) {},
                  )
                : null,
          ),
          child: !exists
              ? const Icon(Icons.music_note, color: Colors.white54)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HoverableText(
                text: track.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                onTap: album != null ? () => onOpenAlbum(album) : null,
              ),
              const SizedBox(height: 2),
              // SingleChildScrollView horizontal plutot que Wrap : avec
              // plusieurs artistes (feat.) le Wrap passait a la ligne et
              // faisait deborder verticalement la barre de lecture (hauteur
              // fixe). Ici la liste reste sur une seule ligne, simplement
              // tronquee/scrollable si trop longue, sans casser la mise en
              // page -- chaque nom reste individuellement survolable/cliquable.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < artistNames.length; i++) ...[
                      if (i > 0)
                        const Text(', ',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 12)),
                      _HoverableText(
                        text: artistNames[i],
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                        onTap: () => onOpenArtist(artistNames[i]),
                      ),
                    ],
                  ],
                ),
              ),
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
      selector: (_, state) =>
          (state.isShuffled, state.loopMode, state.isPlaying),
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
              icon: loopMode == LoopMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
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
  final Track track;
  const _PlayerExtras({required this.track});

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
            final duration = widget.track.duration.inMilliseconds > 0
                ? widget.track.duration
                : (player.duration ?? Duration.zero);
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
              : (_volume! > 0
                  ? Icons.volume_down_rounded
                  : Icons.volume_off_rounded),
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
        Selector<AppState, bool>(
          selector: (_, state) => state.isJamActive,
          builder: (context, isJamActive, __) => GlassIconButton(
            icon: Icons.groups,
            active: isJamActive,
            size: 18,
            onPressed: () => showJamMenu(context),
          ),
        ),
        GlassIconButton(
          icon: Icons.queue_music,
          size: 18,
          onPressed: () => showQueuePanel(context),
        ),
      ],
    );
  }
}

/// Texte souligne au survol quand cliquable (titre -> album, artiste ->
/// page artiste), comme un lien -- sinon affiche tel quel sans interaction.
class _HoverableText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final VoidCallback? onTap;

  const _HoverableText({
    required this.text,
    required this.style,
    required this.onTap,
  });

  @override
  State<_HoverableText> createState() => _HoverableTextState();
}

class _HoverableTextState extends State<_HoverableText> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.onTap != null && _hover
        ? widget.style.copyWith(decoration: TextDecoration.underline)
        : widget.style;

    final text = Text(widget.text,
        maxLines: 1, overflow: TextOverflow.ellipsis, style: style);

    if (widget.onTap == null) return text;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: text),
    );
  }
}
