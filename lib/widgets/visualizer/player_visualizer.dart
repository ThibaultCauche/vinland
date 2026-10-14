import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import 'pulse_waves_visualizer.dart';

/// [PulseWavesVisualizer] branche sur l'etat de l'app : lecture en cours,
/// couleur de la pochette, reglage Parametres > Lecture > Visuel anime.
/// Rien sur Windows, meme dans une fenetre etroite en affichage mobile.
class PlayerVisualizer extends StatefulWidget {
  const PlayerVisualizer({
    super.key,
    this.origin = Alignment.center,
    this.intensity = 1,
    this.askPermission = false,
  });

  final Alignment origin;
  final double intensity;

  /// Grand lecteur : a la premiere ouverture, propose une fois l'acces au
  /// son pour que le visuel suive vraiment la musique.
  final bool askPermission;

  @override
  State<PlayerVisualizer> createState() => _PlayerVisualizerState();
}

class _PlayerVisualizerState extends State<PlayerVisualizer> {
  @override
  void initState() {
    super.initState();
    if (!widget.askPermission) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      if (!state.playbackSettings.visualizerEnabled) return;
      state.visualizer.askPermissionOnce(_explain);
    });
  }

  Future<bool> _explain() async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Faire danser le lecteur ?'),
        content: const Text(
          'Pour que les vagues suivent le rythme, Android doit '
          'autoriser Vinland à analyser le son. Il appelle ça « micro », '
          'mais Vinland n\'écoute que sa propre musique, jamais ce qui se '
          'dit autour.\n\nSans ça, le visuel pulse tout seul.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Autoriser'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return ListenableBuilder(
      listenable: state.playbackSettings,
      builder: (context, _) {
        // Android seulement (demande de Thibault) : une fenetre Windows
        // etroite passe en affichage mobile, sans visuel pour autant.
        if (!state.visualizer.supported ||
            !state.playbackSettings.visualizerEnabled) {
          return const SizedBox.shrink();
        }
        return Selector<AppState, (bool, Color?)>(
          selector: (_, s) => (s.displayIsPlaying, s.dominantColor),
          builder: (context, data, _) => PulseWavesVisualizer(
            visualizer: state.visualizer,
            playing: data.$1,
            color: PulseWavesVisualizer.colorFromCover(data.$2),
            origin: widget.origin,
            intensity: widget.intensity,
          ),
        );
      },
    );
  }
}
