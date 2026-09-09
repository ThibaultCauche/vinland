import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import 'desktop_hero_card.dart';
import 'desktop_track_row.dart';
import 'glass.dart';

/// Vue generique "collection de titres" (playlist, album ou artiste) :
/// hero card + liste, reutilisee par les trois car la reference Behance
/// montre exactement cette mise en page pour une playlist.
class DesktopCollectionView extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? coverPath;
  final List<Track> tracks;
  final bool? isLiked;
  final VoidCallback? onToggleLike;
  final VoidCallback onBack;

  const DesktopCollectionView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.coverPath,
    required this.tracks,
    required this.onBack,
    this.isLiked,
    this.onToggleLike,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final songCount = '${tracks.length} titre${tracks.length > 1 ? 's' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GlassIconButton(icon: Icons.arrow_back_rounded, onPressed: onBack),
          ],
        ),
        const SizedBox(height: 12),
        DesktopHeroCard(
          title: title,
          subtitle: subtitle,
          metaLabel: songCount,
          coverPath: coverPath,
          isLiked: isLiked ?? false,
          onToggleLike: onToggleLike,
          onShuffle: tracks.isEmpty
              ? () {}
              : () {
                  final shuffled = List<Track>.of(tracks)..shuffle();
                  state.playTrack(shuffled.first, trackList: shuffled);
                },
        ),
        const SizedBox(height: 20),
        Expanded(
          child: tracks.isEmpty
              ? const Center(
                  child: Text('Aucun titre', style: TextStyle(color: Colors.white38)),
                )
              : Selector<AppState, Track?>(
                  selector: (_, s) => s.currentTrack,
                  builder: (context, currentTrack, __) {
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: tracks.length,
                      itemBuilder: (context, i) {
                        final track = tracks[i];
                        return DesktopTrackRow(
                          track: track,
                          isPlaying: currentTrack?.id == track.id,
                          onTap: () => state.playTrack(track, trackList: tracks),
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
