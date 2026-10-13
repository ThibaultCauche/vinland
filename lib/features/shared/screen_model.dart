import 'package:flutter/foundation.dart';

import '../../models/discovered_track.dart';
import '../../services/download_worker_service.dart';
import 'library_port.dart';

/// Attend la fin d'un telechargement demande au worker NAS. Chaque vue
/// choisit comment : popup de progression (showDownloadProgressDialog) ou
/// attente silencieuse (worker.waitForCompletion) -- voir download_waiters.
typedef DownloadWaiter = Future<DownloadJobStatus> Function(
    DownloadWorkerService worker, String jobId);

/// Base des view-models partages entre l'ecran mobile et la vue desktop
/// d'une meme page (artiste, album, recherche...). Avant, chaque paire de
/// vues avait sa propre copie de ce code (ecoute de fin de synchro, etats
/// de telechargement par titre), corrigee parfois d'un cote seulement.
///
/// La vue cree le modele dans initState, l'ecoute pour se redessiner et le
/// libere dans dispose ; elle ne garde que la mise en page.
abstract class ScreenModel extends ChangeNotifier {
  ScreenModel({required this.library, DownloadWorkerService? downloadWorker})
      : downloadWorker = downloadWorker ?? DownloadWorkerService(),
        _wasSyncing = library.isSyncing {
    library.addListener(_onLibraryChanged);
  }

  final LibraryPort library;
  final DownloadWorkerService downloadWorker;

  bool _wasSyncing;
  bool _disposed = false;
  final Map<int, DownloadUiState> _downloadStates = {};

  /// Vrai une fois la vue fermee : les chargements encore en vol ne doivent
  /// plus rien publier (equivalent du `mounted` des anciens State).
  bool get isDisposed => _disposed;

  bool get canDownload => downloadWorker.isConfigured;

  DownloadUiState? downloadStateOf(int discoveredTrackId) =>
      _downloadStates[discoveredTrackId];

  /// Si la page a ete ouverte pendant que la bibliotheque NAS finissait de
  /// charger, le statut "possede" calcule alors serait fige et faux pour le
  /// reste de la session : on recharge une fois la synchro terminee.
  void _onLibraryChanged() {
    final syncing = library.isSyncing;
    if (_wasSyncing && !syncing && !_disposed) onSyncFinished();
    _wasSyncing = syncing;
  }

  /// Appele quand une synchro NAS se termine pendant que la page est
  /// ouverte. Rien par defaut.
  @protected
  void onSyncFinished() {}

  /// Appele apres qu'un titre demande au worker est arrive sur le NAS, avant
  /// que son icone de telechargement disparaisse. Rien par defaut.
  @protected
  Future<void> onTrackDownloaded(DiscoveredTrack track) async {}

  /// notifyListeners() sans risque apres fermeture de la vue.
  @protected
  void changed() {
    if (!_disposed) notifyListeners();
  }

  /// Demande le telechargement d'un titre absent du NAS au worker (voir
  /// DownloadWorkerService) puis le fait apparaitre dans la bibliotheque.
  /// Retourne true si le titre est arrive.
  Future<bool> downloadTrack(DiscoveredTrack track,
      {required DownloadWaiter wait}) async {
    _downloadStates[track.id] = DownloadUiState.downloading;
    changed();

    final jobId = await downloadWorker.requestDownload(
      artist: track.artistName,
      title: track.title,
      // "Inconnu" est un texte d'affichage (voir DiscoveredTrack.fromJson),
      // pas un vrai nom d'album Deezer -- ne pas l'envoyer au worker, sinon
      // le morceau atterrit dans un dossier "Inconnu" sur le NAS.
      album: track.albumName == 'Inconnu' ? null : track.albumName,
    );
    if (jobId == null) {
      _downloadStates[track.id] = DownloadUiState.failed;
      changed();
      return false;
    }
    if (_disposed) return false;

    final status = await wait(downloadWorker, jobId);
    if (_disposed) return false;

    if (status.state != DownloadJobState.done) {
      _downloadStates[track.id] = DownloadUiState.failed;
      changed();
      return false;
    }
    // handleTrackDownloaded (pas un syncNavidrome() complet, qui reconstruit
    // toute la bibliotheque lot par lot et la rend temporairement
    // injouable) : voir son commentaire dans AppState.
    await library.handleTrackDownloaded(track.artistName, track.title);
    if (_disposed) return false;
    await onTrackDownloaded(track);
    if (_disposed) return false;
    _downloadStates.remove(track.id);
    changed();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    library.removeListener(_onLibraryChanged);
    super.dispose();
  }
}
