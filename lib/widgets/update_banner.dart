import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_state.dart';
import '../services/android_updater_service.dart';
import '../services/self_updater_service.dart';
import '../services/update_check_service.dart';

/// Bandeau affiche sur l'accueil des qu'une nouvelle version est disponible.
/// Sur Windows avec un asset zip trouve : declenche l'auto-update complet
/// (fermeture/remplacement/relance). Sur Android avec un asset APK trouve :
/// telecharge l'APK et ouvre l'installeur systeme directement (l'utilisateur
/// doit quand meme confirmer l'installation, Android l'exige). Sinon (asset
/// manquant) : ouvre juste la page de release dans le navigateur.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, UpdateInfo?>(
      selector: (_, state) => state.updateInfo,
      builder: (context, update, child) {
        if (update == null) return const SizedBox.shrink();

        final isWindows = defaultTargetPlatform == TargetPlatform.windows;
        final isAndroid = defaultTargetPlatform == TargetPlatform.android;
        final canAutoUpdate =
            (isWindows && update.windowsDownloadUrl != null) ||
                (isAndroid && update.androidDownloadUrl != null);
        final autoUpdateUrl =
            isWindows ? update.windowsDownloadUrl : update.androidDownloadUrl;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Material(
            color: const Color(0xFF1B2E20),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => canAutoUpdate
                  ? _confirmAutoUpdate(context, autoUpdateUrl!, isWindows)
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

  void _confirmAutoUpdate(BuildContext context, String downloadUrl, bool isWindows) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title:
            const Text('Mettre a jour', style: TextStyle(color: Colors.white)),
        content: Text(
          isWindows
              ? "L'app va se fermer, se mettre a jour, puis redemarrer automatiquement. "
                  "Ca prend quelques secondes."
              : "L'app va telecharger la mise a jour puis te proposera de "
                  "l'installer -- Android demande de confirmer toi-meme "
                  "l'installation.",
          style: const TextStyle(color: Colors.white70),
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
              _runAutoUpdate(context, downloadUrl, isWindows);
            },
            child: const Text('Mettre a jour',
                style: TextStyle(color: Color(0xFF1DB954))),
          ),
        ],
      ),
    );
  }

  void _runAutoUpdate(BuildContext context, String downloadUrl, bool isWindows) {
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

    final future = isWindows
        ? SelfUpdaterService().downloadAndApply(downloadUrl)
        : AndroidUpdaterService().downloadAndInstall(downloadUrl);

    future.then((ok) {
      // Sur Windows, ok == true signifie que downloadAndApply() a deja
      // appele exit(0) : on n'arrive ici que dans le cas d'un echec. Sur
      // Android, ok == true signifie juste que l'installeur systeme a bien
      // ete lance (l'app continue de tourner en-dessous) -- on ferme le
      // dialogue de chargement dans les deux cas de succes/echec puisqu'il
      // n'y a plus rien a attendre.
      if (context.mounted) {
        Navigator.pop(context);
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    "Echec de la mise a jour automatique -- reessaie plus tard.")),
          );
        }
      }
    });
  }
}
