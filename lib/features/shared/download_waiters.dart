import 'package:flutter/widgets.dart';

import '../../services/download_worker_service.dart';
import '../../widgets/download_progress_dialog.dart';
import 'screen_model.dart';

/// Suit le telechargement dans un popup de progression (tap sur une ligne).
DownloadWaiter waitWithProgressDialog(BuildContext context) =>
    (worker, jobId) =>
        showDownloadProgressDialog(context, worker: worker, jobId: jobId);

/// Attend sans popup : pour les telechargements groupes ("Telecharger (N
/// titres)"), ou un popup par titre s'empilerait sur le meme Navigator et
/// seul le dernier resterait pilotable. L'icone de ligne reste le retour
/// visuel.
Future<DownloadJobStatus> waitSilently(
        DownloadWorkerService worker, String jobId) =>
    worker.waitForCompletion(jobId);
