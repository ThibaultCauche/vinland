import 'package:flutter/material.dart';

import '../controllers/playback_settings.dart';
import '../domain/replay_gain.dart';

/// Section « Lecture » des parametres (mobile et desktop) : fondu enchaine
/// et normalisation du volume.
class PlaybackSettingsTiles extends StatelessWidget {
  const PlaybackSettingsTiles({super.key, required this.settings});

  final PlaybackSettings settings;

  static const _accent = Color(0xFF1DB954);

  static String crossfadeLabel(Duration d) =>
      d == Duration.zero ? 'Désactivé' : '${d.inSeconds} s';

  static const _modeLabels = {
    ReplayGainMode.off: 'Non',
    ReplayGainMode.track: 'Par titre',
    ReplayGainMode.album: 'Par album',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.swap_horiz, color: Colors.white54),
            title: const Text('Fondu enchaîné',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'Les titres se chevauchent au changement (sauf ceux qui '
                's\'enchaînent sur un même album)',
                style: TextStyle(color: Colors.white54)),
            trailing: Text(crossfadeLabel(settings.crossfade),
                style: const TextStyle(color: Colors.white)),
          ),
          Slider(
            value: settings.crossfade.inSeconds.toDouble(),
            min: 0,
            max: PlaybackSettings.maxCrossfade.inSeconds.toDouble(),
            divisions: PlaybackSettings.maxCrossfade.inSeconds,
            label: crossfadeLabel(settings.crossfade),
            activeColor: _accent,
            onChanged: (v) =>
                settings.setCrossfade(Duration(seconds: v.round())),
          ),
          const ListTile(
            leading: Icon(Icons.equalizer, color: Colors.white54),
            title:
                Text('Volume égalisé', style: TextStyle(color: Colors.white)),
            subtitle: Text(
                'Baisse les titres trop forts (tags ReplayGain du serveur)',
                style: TextStyle(color: Colors.white54)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<ReplayGainMode>(
              segments: [
                for (final mode in ReplayGainMode.values)
                  ButtonSegment(value: mode, label: Text(_modeLabels[mode]!)),
              ],
              selected: {settings.replayGainMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => settings.setReplayGainMode(s.first),
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? Colors.black
                        : Colors.white),
                backgroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected) ? _accent : null),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
