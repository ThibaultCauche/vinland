import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

/// Petit cercle vert qui tourne pendant une synchro -- discret, a placer
/// pres de l'avatar/la recherche (mobile) ou dans la sidebar (desktop,
/// voir DesktopSidebar). Remplace l'ancien gros bandeau texte plein
/// largeur qui occupait la home a chaque synchro (retour testeurs : trop
/// intrusif pour un etat aussi frequent).
class SyncIndicator extends StatelessWidget {
  final double size;
  const SyncIndicator({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, bool>(
      selector: (_, state) => state.isSyncing,
      builder: (context, isSyncing, __) {
        if (!isSyncing) return const SizedBox.shrink();
        return Tooltip(
          message: 'Synchronisation en cours...',
          child: SizedBox(
            width: size,
            height: size,
            child: const CircularProgressIndicator(
                color: Color(0xFF1DB954), strokeWidth: 2),
          ),
        );
      },
    );
  }
}

/// Rend visible ce qui se passait avant en silence total : la toute
/// premiere synchro (cache local vide) peut prendre du temps ou echouer
/// (NAS/Tailscale Funnel injoignable), et sans ce bandeau l'app semblait
/// juste vide/cassee -- exactement ce qu'un ami testeur a rencontre. Ne
/// couvre plus que ce cas d'erreur : la synchro en cours (etat frequent,
/// pas une erreur) est signalee par le petit SyncIndicator ci-dessus a la
/// place.
class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (bool, bool)>(
      selector: (_, state) => (state.lastSyncEmpty, state.allTracks.isEmpty),
      builder: (context, data, child) {
        final (lastSyncEmpty, hasNoTracks) = data;
        final state = context.read<AppState>();

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
