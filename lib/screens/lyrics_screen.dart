import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../navigation/overlay_navigator.dart';
import '../providers/app_state.dart';
import '../widgets/player/lyrics_view.dart';

/// Paroles en plein ecran (mobile), ouvertes depuis le lecteur. Meme fond
/// que le lecteur, aux couleurs de la pochette.
class LyricsScreen extends StatelessWidget implements SingleInstanceOverlay {
  const LyricsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (Track?, Color?)>(
      selector: (_, state) => (state.displayTrack, state.dominantColor),
      builder: (context, data, _) {
        final (track, dominantColor) = data;
        final top = dominantColor != null
            ? Color.lerp(dominantColor, Colors.black, 0.4)!
            : const Color(0xFF121212);
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: top,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.expand_more, color: Colors.white),
              onPressed: () => context.read<AppState>().popOverlay(),
            ),
            title: track == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text(track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13)),
                    ],
                  ),
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, const Color(0xFF121212)],
              ),
            ),
            child: const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: LyricsView(),
              ),
            ),
          ),
        );
      },
    );
  }
}
