import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

/// Rend visible ce qui se passait avant en silence total : la toute
/// premiere synchro (cache local vide) peut prendre du temps ou echouer
/// (NAS/Tailscale Funnel injoignable), et sans ce bandeau l'app semblait
/// juste vide/cassee -- exactement ce qu'un ami testeur a rencontre.
class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (bool, bool, bool)>(
      selector: (_, state) =>
          (state.isSyncing, state.lastSyncEmpty, state.allTracks.isEmpty),
      builder: (context, data, child) {
        final (isSyncing, lastSyncEmpty, hasNoTracks) = data;
        final state = context.read<AppState>();

        if (isSyncing) {
          return _Banner(
            color: const Color(0xFF1E1E1E),
            icon: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  color: Color(0xFF1DB954), strokeWidth: 2),
            ),
            text: 'Synchronisation de ta bibliotheque avec le serveur...',
          );
        }

        if (lastSyncEmpty && hasNoTracks) {
          return _Banner(
            color: const Color(0xFF3A2020),
            icon: const Icon(Icons.wifi_off, color: Colors.orangeAccent, size: 20),
            text: 'Aucun titre trouve -- verifie que le serveur Navidrome '
                'est joignable.',
            actionLabel: 'Reessayer',
            onAction: () => state.syncNavidrome(),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final Widget icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Banner({
    required this.color,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!,
                    style: const TextStyle(color: Color(0xFF1DB954))),
              ),
          ],
        ),
      ),
    );
  }
}
