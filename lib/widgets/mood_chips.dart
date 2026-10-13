import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/moods.dart';
import '../providers/app_state.dart';

/// Rangee « Ton mood » de l'accueil (mobile et desktop) : un appui lance
/// en aleatoire les titres de la bibliotheque du genre correspondant.
/// N'affiche que les moods qui ont assez de titres pour tenir une ecoute.
class MoodChips extends StatelessWidget {
  const MoodChips({super.key});

  static const _minTracks = 5;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final available = [
      for (final mood in moods)
        if (tracksForMood(mood, state.allTracks).length >= _minTracks) mood
    ];
    // Bibliotheque sans genres dans les tags : pas de section vide.
    if (available.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ton mood',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _chips(state, available),
        ],
      ),
    );
  }

  Widget _chips(AppState state, List<Mood> available) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mood in available)
          ActionChip(
            label: Text(mood.label),
            labelStyle: const TextStyle(color: Colors.white),
            backgroundColor: const Color(0xFF2A2A2A),
            side: BorderSide.none,
            onPressed: () {
              final tracks = tracksForMood(mood, state.allTracks)..shuffle();
              state.playTrack(tracks.first, trackList: tracks);
            },
          ),
      ],
    );
  }
}
