import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../navigation/overlay_navigator.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../screens/album_screen.dart';
import '../screens/lyrics_screen.dart';
import '../screens/queue_screen.dart';
import 'album_options_sheet.dart';
import 'player/cast_devices_section.dart';
import 'player/jam_controls.dart';
import 'player/like_button.dart';
import 'player/play_pause_button.dart';
import 'player/player_slider.dart';
import 'player/player_cover.dart';
import 'player/player_options_sheet.dart';
import 'visualizer/player_visualizer.dart';

class PlayerScreen extends StatefulWidget implements SingleInstanceOverlay {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  /// Les vagues du visuel partent du centre de la pochette.
  final _coverKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (Track?, Color?, bool, LoopMode)>(
      selector: (_, state) => (
        state.displayTrack,
        state.dominantColor,
        state.isShuffled,
        state.loopMode,
      ),
      builder: (context, data, child) {
        final (track, dominantColor, isShuffled, loopMode) = data;
        if (track == null) return const SizedBox.shrink();

        return Scaffold(
          backgroundColor: Colors.transparent,
          // Le fond et les vagues passent aussi sous la barre du haut.
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.expand_more, color: Colors.white),
              onPressed: () => context.read<AppState>().popOverlay(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.lyrics_outlined, color: Colors.white),
                tooltip: 'Paroles',
                onPressed: () =>
                    context.read<AppState>().pushOverlay(const LyricsScreen()),
              ),
              IconButton(
                icon: const Icon(Icons.queue_music, color: Colors.white),
                tooltip: 'File d\'attente',
                onPressed: () =>
                    context.read<AppState>().pushOverlay(const QueueScreen()),
              ),
              // Bouton reel a cote de la file d'attente (voir showDeviceMenu),
              // pas cache dans les options -- meme visibilite que cote
              // desktop (desktop_player_bar.dart), retour utilisateur.
              Selector<AppState, bool>(
                selector: (_, state) =>
                    state.isPersonalSyncParticipant ||
                    state.connectedParticipantDeviceName != null,
                builder: (context, isConnected, __) => ListenableBuilder(
                  listenable: context.read<AppState>().cast,
                  builder: (context, _) {
                    final cast = context.read<AppState>().cast;
                    return IconButton(
                      icon: Icon(deviceMenuIcon(cast),
                          color: isConnected || cast.isCasting
                              ? const Color(0xFF1DB954)
                              : Colors.white),
                      tooltip: deviceMenuTooltip(cast),
                      onPressed: () => showDeviceMenu(context),
                    );
                  },
                ),
              ),
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
            child: Stack(
              children: [
                // Vagues lumineuses derriere tout le lecteur ; elles
                // partent de la pochette.
                Positioned.fill(
                  child: PlayerVisualizer(
                    origin: const Alignment(0, -0.35),
                    originKey: _coverKey,
                    intensity: 0.8,
                    askPermission: true,
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const Spacer(flex: 2),
                        PlayerCover(key: _coverKey, coverPath: track.coverPath),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      final state = context.read<AppState>();
                                      state.pushOverlay(AlbumScreen(
                                        album: resolveTrackAlbum(state, track),
                                        scrollToTrackId: track.id,
                                      ));
                                    },
                                    child: Text(
                                      track.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  GestureDetector(
                                    onTap: () =>
                                        showArtistAlbumPicker(context, track),
                                    child: Text(
                                      track.artist,
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PlayerLikeButton(trackId: track.id),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const RepaintBoundary(child: PlayerSlider()),
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
                              onPressed: () =>
                                  context.read<AppState>().nextTrack(),
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
              ],
            ),
          ),
        );
      },
    );
  }
}
