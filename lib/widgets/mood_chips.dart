import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/moods.dart';
import '../models/track.dart';
import '../providers/app_state.dart';
import '../services/lastfm_service.dart';

/// Rangee « Ton mood » de l'accueil (mobile et desktop) : un appui lance
/// en aleatoire les titres de la bibliotheque du genre correspondant
/// (moods par genre, seulement ceux qui ont assez de titres), puis une
/// rangee « Humeur » tiree des tags Last.fm quand la cle est configuree.
class MoodChips extends StatelessWidget {
  const MoodChips({super.key});

  static const _minTracks = 5;
  static final _lastfm = LastfmService();

  /// Resultat Last.fm par tag, garde le temps de la session : la liste des
  /// titres associes a « sad » ne change pas d'une minute a l'autre.
  static final _tagCache = <String, List<(String, String)>>{};

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final available = [
      for (final mood in moods)
        if (tracksForMood(mood, state.allTracks).length >= _minTracks) mood
    ];
    // Ni genres dans les tags ni cle Last.fm : pas de section vide.
    if (available.isEmpty && !_lastfm.isConfigured) {
      return const SizedBox.shrink();
    }
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
          _chips([
            for (final mood in available)
              (
                mood.label,
                () => _play(context, tracksForMood(mood, state.allTracks)),
              ),
          ]),
          if (_lastfm.isConfigured) ...[
            const SizedBox(height: 12),
            const Text('Humeur',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 8),
            _chips([
              for (final (label, tag) in lastfmMoods)
                (label, () => _playLastfm(context, tag)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _chips(List<(String, VoidCallback)> items) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, onPressed) in items)
          ActionChip(
            label: Text(label),
            labelStyle: const TextStyle(color: Colors.white),
            backgroundColor: const Color(0xFF2A2A2A),
            side: BorderSide.none,
            onPressed: onPressed,
          ),
      ],
    );
  }

  static Future<void> _playLastfm(BuildContext context, String tag) async {
    final messenger = ScaffoldMessenger.of(context);
    final library = context.read<AppState>().allTracks;
    final candidates = _tagCache[tag] ??= await _lastfm.topTracksForTag(tag);
    final tracks = matchInLibrary(candidates, library);
    if (tracks.length < _minTracks) {
      if (candidates.isEmpty) _tagCache.remove(tag); // reseau : retenter
      messenger.showSnackBar(const SnackBar(
        content: Text('Pas assez de titres de ta bibliothèque pour cette '
            'humeur'),
        backgroundColor: Color(0xFF2A2A2A),
      ));
      return;
    }
    if (context.mounted) _play(context, tracks);
  }

  static void _play(BuildContext context, List<Track> tracks) {
    if (tracks.isEmpty) return;
    tracks.shuffle();
    context.read<AppState>().playTrack(tracks.first, trackList: tracks);
  }
}
