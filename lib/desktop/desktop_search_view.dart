import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import 'desktop_track_row.dart';
import 'glass.dart';

/// Recherche desktop, volontairement simple (titres locaux uniquement) :
/// on pourra brancher la decouverte Deezer comme sur mobile plus tard.
class DesktopSearchView extends StatefulWidget {
  const DesktopSearchView({super.key});

  @override
  State<DesktopSearchView> createState() => _DesktopSearchViewState();
}

class _DesktopSearchViewState extends State<DesktopSearchView> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final results = _query.isEmpty ? <Track>[] : state.musicService.searchTracks(_query);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassPanel(
          borderRadius: BorderRadius.circular(24),
          blurSigma: 0,
          tint: Colors.white.withOpacity(0.06),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.white54, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Titres, artistes, albums...',
                      hintStyle: TextStyle(color: Colors.white38),
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: _query.isEmpty
              ? const Center(
                  child: Text('Recherchez un titre, un artiste ou un album',
                      style: TextStyle(color: Colors.white38)),
                )
              : results.isEmpty
                  ? const Center(
                      child: Text('Aucun resultat', style: TextStyle(color: Colors.white38)))
                  : Selector<AppState, Track?>(
                      selector: (_, s) => s.currentTrack,
                      builder: (context, currentTrack, __) {
                        return ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (context, i) {
                            final track = results[i];
                            return DesktopTrackRow(
                              track: track,
                              isPlaying: currentTrack?.id == track.id,
                              onTap: () => state.playTrack(track, trackList: results),
                              onLike: () => state.toggleLike(track.id),
                              onMore: () {},
                            );
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
