import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_state.dart';
import '../services/self_updater_service.dart';
import '../services/update_check_service.dart';

/// Bandeau affiche sur l'accueil des qu'une nouvelle version est disponible.
/// Sur Windows avec un asset zip trouve : declenche l'auto-update complet
/// (fermeture/remplacement/relance). Sinon (Android, ou asset manquant) :
/// ouvre juste la page de release dans le navigateur.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, UpdateInfo?>(
      selector: (_, state) => state.updateInfo,
      builder: (context, update, child) {
        if (update == null) return const SizedBox.shrink();

        final canAutoUpdate =
            defaultTargetPlatform == TargetPlatform.windows &&
                update.windowsDownloadUrl != null;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Material(
            color: const Color(0xFF1B2E20),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => canAutoUpdate
                  ? _confirmAutoUpdate(context, update.windowsDownloadUrl!)
                  : launchUrl(Uri.parse(update.releaseUrl),
                      mode: LaunchMode.externalApplication),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_circle_down,
                        color: Color(0xFF1DB954), size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Mise a jour disponible',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                          Text(
                            canAutoUpdate
                                ? 'Vinland ${update.latestVersion} -- toucher pour installer'
                                : 'Vinland ${update.latestVersion} -- toucher pour telecharger',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white38),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _confirmAutoUpdate(BuildContext context, String downloadUrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title:
            const Text('Mettre a jour', style: TextStyle(color: Colors.white)),
        content: const Text(
          "L'app va se fermer, se mettre a jour, puis redemarrer automatiquement. "
          "Ca prend quelques secondes.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _runAutoUpdate(context, downloadUrl);
            },
            child: const Text('Mettre a jour',
                style: TextStyle(color: Color(0xFF1DB954))),
          ),
        ],
      ),
    );
  }

  void _runAutoUpdate(BuildContext context, String downloadUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        backgroundColor: Color(0xFF1E1E1E),
        content: Row(
          children: [
            CircularProgressIndicator(color: Color(0xFF1DB954)),
            SizedBox(width: 20),
            Expanded(
              child: Text('Telechargement de la mise a jour...',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    SelfUpdaterService().downloadAndApply(downloadUrl).then((ok) {
      // Si ok == true, downloadAndApply() a deja appele exit(0) : on
      // n'arrive ici que dans le cas d'un echec.
      if (!ok && context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "Echec de la mise a jour automatique -- reessaie plus tard.")),
        );
      }
    });
  }
}
