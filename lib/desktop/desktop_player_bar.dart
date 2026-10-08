import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
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
    return Selector<AppState, (Track?, bool, String?)>(
      selector: (_, state) => (
        state.displayTrack,
        state.isPersonalSyncParticipant,
        state.remoteDeviceName,
      ),
      builder: (context, data, _) {
        final (track, isRemote, remoteDeviceName) = data;

        // Barre normale dans tous les cas (voir AppState.displayTrack/
        // displayIsPlaying/displayPosition) : avant, un autre appareil du
        // meme compte hote remplaçait toute la barre par _RemotePlayingRow,
        // une version tronquee (pas de barre de progression, pas de volume,
        // pas de titre cliquable...) -- retour utilisateur : "j'aimerais
        // avoir le lecteur de base". isRemote sert juste a rediriger la
        // source de la position/du titre affiche, pas a changer la mise en
        // page.
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
                      Transform.translate(
                        offset: const Offset(0, 6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: RepaintBoundary(
                              child:
                                  _SeekBar(track: track, isRemote: isRemote)),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 300,
                                child: _NowPlayingInfo(
                                  track: track,
                                  deviceName: isRemote ? remoteDeviceName : null,
                                  onOpenAlbum: onOpenAlbum,
                                  onOpenArtist: onOpenArtist,
                                ),
                              ),
                              const Expanded(child: _TransportControls()),
                              SizedBox(
                                width: 300,
                                child: RepaintBoundary(
                                    child: _PlayerExtras(
                                        track: track, isRemote: isRemote)),
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
  final bool isRemote;
  const _SeekBar({required this.track, required this.isRemote});

  @override
  Widget build(BuildContext context) {
    // En synchro perso participant, rien ne joue localement : la position
    // vient de la derniere valeur reçue de l'hote (voir
    // AppState.displayPosition), pas du moteur audio local.
    if (isRemote) {
      return Selector<AppState, Duration>(
        selector: (_, state) => state.displayPosition,
        builder: (context, position, __) => _buildSlider(context, position,
            track.duration.inMilliseconds > 0 ? track.duration : Duration.zero),
      );
    }
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
        return _buildSlider(context, position, duration);
      },
    );
  }

  Widget _buildSlider(BuildContext context, Duration position, Duration duration) {
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
  }
}

class _NowPlayingInfo extends StatelessWidget {
  final Track track;
  // Non-null seulement en synchro perso participant (voir
  // AppState.isPersonalSyncParticipant) : precise sur quel appareil ca joue
  // vraiment, la barre normale ne le montrant sinon nulle part.
  final String? deviceName;
  final void Function(Album album) onOpenAlbum;
  final void Function(String artistName) onOpenArtist;

  const _NowPlayingInfo({
    required this.track,
    this.deviceName,
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
        // Flexible (pas Expanded) : le coeur doit rester colle au bloc
        // titre/artiste au lieu d'etre pousse jusqu'au bord du bloc de 300px
        // quand titre+artiste sont courts (retour utilisateur). Le bloc
        // reste quand meme borne a l'espace disponible pour les titres
        // longs, via shrinkWrap sur le marquee ci-dessous (voir
        // _ArtistNamesMarquee).
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (deviceName != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.devices,
                        color: Colors.white38, size: 11),
                    const SizedBox(width: 3),
                    Text('En lecture sur $deviceName',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10)),
                  ],
                ),
              _HoverableText(
                text: track.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                onTap: album != null ? () => onOpenAlbum(album) : null,
              ),
              const SizedBox(height: 2),
              _ArtistNamesMarquee(
                artistNames: artistNames,
                onOpenArtist: onOpenArtist,
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
            tooltip: isLiked ? 'Retirer' : 'Aimer',
            onPressed: () => context.read<AppState>().toggleLike(track.id),
          ),
        ),
      ],
    );
  }
}

/// Liste d'artistes en defilement automatique quand elle deborde de la
/// largeur disponible (feat. a rallonge) -- boucle droite jusqu'au bout,
/// pause, retour au debut, pause, etc. S'arrete au survol pour laisser le
/// temps de lire/cliquer un nom precis (chaque nom reste individuellement
/// cliquable vers sa page artiste, comme avant). Ne fait rien si le texte
/// tient deja dans la largeur (defilement inutile).
class _ArtistNamesMarquee extends StatefulWidget {
  final List<String> artistNames;
  final void Function(String artistName) onOpenArtist;

  const _ArtistNamesMarquee({
    required this.artistNames,
    required this.onOpenArtist,
  });

  @override
  State<_ArtistNamesMarquee> createState() => _ArtistNamesMarqueeState();
}

class _ArtistNamesMarqueeState extends State<_ArtistNamesMarquee>
    with SingleTickerProviderStateMixin {
  static const _pxPerSecond = 24.0;
  static const _edgePauseMs = 1000.0;

  final _scrollController = ScrollController();
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _pauseRemainingMs = _edgePauseMs;
  bool _atEnd = false;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant _ArtistNamesMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Nouveau morceau (autre liste d'artistes) : repart du debut plutot que
    // de garder un offset qui n'a plus de sens pour ce nouveau texte.
    if (!listEquals(oldWidget.artistNames, widget.artistNames)) {
      _pauseRemainingMs = _edgePauseMs;
      _atEnd = false;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    }
  }

  void _onTick(Duration elapsed) {
    final dtMs = (elapsed - _lastElapsed).inMicroseconds / 1000.0;
    _lastElapsed = elapsed;
    if (_hovering || !_scrollController.hasClients) return;

    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return; // tient dans la largeur dispo : rien a faire

    if (_pauseRemainingMs > 0) {
      _pauseRemainingMs -= dtMs;
      return;
    }

    if (_atEnd) {
      // Pause au bout ecoulee : revient au debut, puis pause a nouveau
      // avant de repartir vers la droite.
      _scrollController.jumpTo(0);
      _atEnd = false;
      _pauseRemainingMs = _edgePauseMs;
      return;
    }

    final next = _scrollController.offset + _pxPerSecond * dtMs / 1000;
    if (next >= max) {
      _scrollController.jumpTo(max);
      _atEnd = true;
      _pauseRemainingMs = _edgePauseMs;
    } else {
      _scrollController.jumpTo(next);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _hovering = true,
      onExit: (_) => _hovering = false,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.artistNames.length; i++) ...[
              if (i > 0)
                const Text(', ',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              _HoverableText(
                text: widget.artistNames[i],
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                onTap: () => widget.onOpenArtist(widget.artistNames[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls();

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (bool, LoopMode, bool)>(
      selector: (_, state) =>
          (state.isShuffled, state.loopMode, state.displayIsPlaying),
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
              tooltip: 'Aléatoire',
              onPressed: state.toggleShuffle,
            ),
            GlassIconButton(
              icon: Icons.skip_previous_rounded,
              size: 24,
              tooltip: 'Précédent',
              onPressed: state.previousTrack,
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: isPlaying ? 'Pause' : 'Lecture',
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: state.togglePlayPause,
                  mouseCursor: SystemMouseCursors.click,
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
            ),
            const SizedBox(width: 4),
            GlassIconButton(
              icon: Icons.skip_next_rounded,
              size: 24,
              tooltip: 'Suivant',
              onPressed: state.nextTrack,
            ),
            GlassIconButton(
              icon: loopMode == LoopMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              active: loopMode != LoopMode.off,
              size: 18,
              tooltip: 'Répéter',
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
  final bool isRemote;
  const _PlayerExtras({required this.track, required this.isRemote});

  @override
  State<_PlayerExtras> createState() => _PlayerExtrasState();
}

class _PlayerExtrasState extends State<_PlayerExtras> {
  double? _volume;

  Widget _positionText(BuildContext context) {
    // Volontairement pas remote-aware au-dela de la position affichee : le
    // volume ci-dessous reste local (voir AppState.remotePlayTrack, pas
    // encore de commande "volume" dans le protocole -- controler le son de
    // l'autre appareil depuis ici n'aurait de toute facon aucun effet audible
    // tant que ce n'est pas lui qui joue).
    if (widget.isRemote) {
      return Selector<AppState, Duration>(
        selector: (_, state) => state.displayPosition,
        builder: (context, position, __) {
          final duration = widget.track.duration.inMilliseconds > 0
              ? widget.track.duration
              : Duration.zero;
          return Text(
            '${formatDuration(position)} / ${formatDuration(duration)}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          );
        },
      );
    }
    final player = context.read<AppState>().player;
    return StreamBuilder<Duration>(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<AppState>().player;
    _volume ??= player.volume;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _positionText(context),
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
          selector: (_, state) => state.isFriendJamActive,
          builder: (context, isFriendJamActive, __) => GlassIconButton(
            icon: Icons.groups,
            active: isFriendJamActive,
            size: 18,
            tooltip: 'Jam',
            onPressed: () => showJamMenu(context),
          ),
        ),
        GlassIconButton(
          icon: Icons.queue_music,
          size: 18,
          tooltip: 'File',
          onPressed: () => showQueuePanel(context),
        ),
        Selector<AppState, bool>(
          selector: (_, state) =>
              state.isPersonalSyncParticipant ||
              state.connectedParticipantDeviceName != null,
          builder: (context, isConnected, __) => GlassIconButton(
            icon: Icons.devices,
            active: isConnected,
            size: 18,
            tooltip: 'Périphériques',
            onPressed: () => showDeviceMenu(context),
          ),
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
