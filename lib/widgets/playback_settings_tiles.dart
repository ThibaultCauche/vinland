import 'package:flutter/material.dart';

import '../controllers/playback_settings.dart';
import '../domain/replay_gain.dart';
import '../services/audio_visualizer.dart';

/// Section « Lecture » des parametres (mobile et desktop) : fondu enchaine,
/// normalisation du volume et visuel anime du lecteur.
class PlaybackSettingsTiles extends StatelessWidget {
  const PlaybackSettingsTiles({
    super.key,
    required this.settings,
    this.visualizer,
  });

  final PlaybackSettings settings;

  /// Pour le reglage du visuel ; absent = pas de reglage (shell desktop,
  /// qui n'affiche pas ce visuel).
  final AudioVisualizer? visualizer;

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
          if (visualizer != null) ...[
            SwitchListTile(
              secondary:
                  const Icon(Icons.hexagon_outlined, color: Colors.white54),
              title: const Text('Visuel animé',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                  'Hexagones qui pulsent au rythme de la musique dans le '
                  'lecteur',
                  style: TextStyle(color: Colors.white54)),
              value: settings.visualizerEnabled,
              activeThumbColor: _accent,
              onChanged: settings.setVisualizerEnabled,
            ),
            if (settings.visualizerEnabled && visualizer!.supported)
              _VisualizerPermissionTile(visualizer: visualizer!),
          ],
        ],
      ),
    );
  }
}

/// Tant que l'acces au son n'est pas donne, le visuel pulse tout seul : ce
/// bouton permet de le donner apres coup (ou de rouvrir les reglages
/// Android si on l'a refuse pour de bon).
class _VisualizerPermissionTile extends StatefulWidget {
  const _VisualizerPermissionTile({required this.visualizer});

  final AudioVisualizer visualizer;

  @override
  State<_VisualizerPermissionTile> createState() =>
      _VisualizerPermissionTileState();
}

class _VisualizerPermissionTileState extends State<_VisualizerPermissionTile> {
  late Future<bool> _granted = widget.visualizer.hasPermission;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _granted,
      builder: (context, snap) {
        if (snap.data ?? true) return const SizedBox.shrink();
        return ListTile(
          leading: const Icon(Icons.graphic_eq, color: Colors.white54),
          title: const Text('Faire réagir le visuel à la musique',
              style: TextStyle(color: Colors.white)),
          subtitle: const Text(
              'Android appelle ça « micro », mais Vinland n\'écoute que sa '
              'propre musique',
              style: TextStyle(color: Colors.white54)),
          onTap: () => setState(() {
            _granted = widget.visualizer.requestPermission();
          }),
        );
      },
    );
  }
}
