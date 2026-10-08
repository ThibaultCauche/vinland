import 'package:flutter/material.dart';
import '../services/download_worker_service.dart';

/// Popup qui affiche l'etape en cours d'une operation suivie par job_id cote
/// download-worker (telechargement : recherche Lidarr, telechargement
/// torrent, repli YouTube, harmonisation des tags, mise a jour bibliotheque
/// ; ou scan de tags global) au lieu du simple spinner opaque qu'affichait
/// waitForCompletion() -- un seul endroit partage par tous les ecrans qui
/// declenchent un telechargement (voir DownloadWorkerService.requestDownload)
/// et par le bouton "Harmoniser la bibliothèque" des parametres (voir
/// DownloadWorkerService.requestTagScan), plutot qu'une jauge de progression
/// reimplementee a chaque appelant.
///
/// Par defaut sonde GET /downloads/<job_id> (worker.getJobStatus) comme
/// avant ; [fetchStatus] permet de sonder un autre endpoint qui repond avec
/// la meme forme JSON (status/stage/error/summary), ex: getTagScanStatus
/// pour /maintenance/tag-scan/<job_id>.
Future<DownloadJobStatus> showDownloadProgressDialog(
  BuildContext context, {
  DownloadWorkerService? worker,
  String? jobId,
  Future<DownloadJobStatus?> Function()? fetchStatus,
  String title = 'Téléchargement',
}) async {
  assert(fetchStatus != null || (worker != null && jobId != null),
      'showDownloadProgressDialog needs either fetchStatus, or worker+jobId');
  final poll = fetchStatus ?? () => worker!.getJobStatus(jobId!);
  final status = await showDialog<DownloadJobStatus>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DownloadProgressDialog(fetchStatus: poll, title: title),
  );
  return status ??
      const DownloadJobStatus(
        state: DownloadJobState.failed,
        error: 'Fenêtre fermée',
      );
}

class _DownloadProgressDialog extends StatefulWidget {
  final Future<DownloadJobStatus?> Function() fetchStatus;
  final String title;

  const _DownloadProgressDialog({
    required this.fetchStatus,
    required this.title,
  });

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  String? _stage;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  Future<void> _poll() async {
    // Meme duree que le timeout Lidarr par defaut cote worker
    // (LIDARR_TIMEOUT_SECONDS=900) plus une marge pour spotdl -- un job qui
    // depasse ca cote worker a de toute facon deja echoue la-bas.
    final deadline = DateTime.now().add(const Duration(minutes: 20));
    while (mounted && !_finished && DateTime.now().isBefore(deadline)) {
      final status = await widget.fetchStatus();
      if (!mounted) return;
      if (status == null) {
        _finish(const DownloadJobStatus(
          state: DownloadJobState.failed,
          error: 'Service de téléchargement injoignable',
        ));
        return;
      }
      if (status.state == DownloadJobState.done ||
          status.state == DownloadJobState.failed) {
        _finish(status);
        return;
      }
      setState(() => _stage = status.stage);
      await Future.delayed(const Duration(seconds: 2));
    }
    if (mounted && !_finished) {
      _finish(const DownloadJobStatus(
        state: DownloadJobState.failed,
        error: 'Délai d\'attente dépassé',
      ));
    }
  }

  void _finish(DownloadJobStatus status) {
    _finished = true;
    if (mounted) Navigator.of(context).pop(status);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(widget.title, style: const TextStyle(color: Colors.white)),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF1DB954),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              downloadStageLabel(_stage),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
