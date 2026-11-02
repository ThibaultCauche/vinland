import '../../services/download_worker_service.dart';
import '../../widgets/app_messenger.dart';

/// Suit en arriere-plan un titre demande au NAS (tap sur une ligne) : un
/// court message au lancement puis a la fin, et l'icone de la ligne qui
/// tourne entre les deux. Avant, une grande fenetre de progression bloquait
/// toute l'app pendant tout le telechargement (retour utilisateur,
/// 2026-11-02 : « je ne peux rien faire d'autre qu'attendre »).
/// Messages via la messagerie de l'app entiere : le message de fin
/// s'affiche meme si on a quitte la page entre-temps.
Future<DownloadJobStatus> waitInBackground(
    DownloadWorkerService worker, String jobId) async {
  showAppMessage(
      'Téléchargement lancé sur le serveur, tu peux continuer à utiliser '
      'l\'app.');
  final status = await worker.waitForCompletion(jobId);
  showAppMessage(status.state == DownloadJobState.done
      ? 'Titre ajouté à ta bibliothèque'
      : 'Échec du téléchargement : ${status.error ?? 'erreur inconnue'}');
  return status;
}

/// Attend sans popup : pour les telechargements groupes ("Telecharger (N
/// titres)"), ou un message par titre serait de trop. L'icone de ligne
/// reste le retour visuel.
Future<DownloadJobStatus> waitSilently(
        DownloadWorkerService worker, String jobId) =>
    worker.waitForCompletion(jobId);
