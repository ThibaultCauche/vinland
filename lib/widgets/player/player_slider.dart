import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';

class PlayerSlider extends StatelessWidget {
  const PlayerSlider({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.read<AppState>().player;
    // Selector plutot que context.read<AppState>().currentTrack : ce widget
    // est instancie en `const` par PlayerScreen (RepaintBoundary(child: const
    // PlayerSlider())), donc son build() n'est jamais rappele par son parent
    // -- sans Selector ici, `track` (et donc la duree/le max du slider)
    // restait fige sur le tout premier morceau lance, meme apres un
    // changement de piste (position affichee depassant la duree, clics sur
    // la barre atterrissant n'importe ou).
    return Selector<AppState, Track?>(
      selector: (_, state) => state.currentTrack,
      builder: (context, track, __) => StreamBuilder<Duration>(
        stream: Stream.periodic(
          const Duration(milliseconds: 200),
          (_) => player.position,
        ),
        builder: (context, posSnap) {
          final position = posSnap.data ?? Duration.zero;
          // Prefere la duree issue des metadonnees NAS (fiable) a celle du
          // moteur de lecture, qui grimpe par paliers en debut de lecture
          // avec media_kit/libmpv (Windows/Linux) sur un flux Navidrome sans
          // Content-Length -- voir mini_player.dart pour le detail.
          final duration = (track != null && track.duration.inMilliseconds > 0)
              ? track.duration
              : (player.duration ?? Duration.zero);
          final max = duration.inSeconds.toDouble().clamp(1, 99999).toDouble();

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
                  value: position.inSeconds.toDouble().clamp(0, max).toDouble(),
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
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    final m = duration.inMinutes;
    final s = duration.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
