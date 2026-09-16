import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../services/download_worker_service.dart';
import '../widgets/track_tile.dart';
import '../widgets/bottom_bar_reserve.dart';

class MissingTracksScreen extends StatefulWidget {
  const MissingTracksScreen({super.key});

  @override
  State<MissingTracksScreen> createState() => _MissingTracksScreenState();
}

class _MissingTracksScreenState extends State<MissingTracksScreen> {
  // Identite (meme reference que dans AppState.missingTracks) plutot que
  // valeur : deux entrees peuvent avoir le meme titre/artiste/album.
  final Set<Map<String, dynamic>> _downloading = {};

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Association manuelle : le fichier est deja sur le NAS (cas typique --
  /// import personnel YouTube/Spotify dont les tags ne collent pas au
  /// matching flou automatique), l'utilisateur le retrouve lui-meme.
  Future<void> _associateManually(Map<String, dynamic> entry) async {
    final state = context.read<AppState>();
    final initialQuery = (entry['title'] ?? '').toString();
    final picked = await showModalBottomSheet<Track>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (_) => _TrackPickerSheet(
        title: 'Associer "$initialQuery" a...',
        initialQuery: initialQuery,
        search: (query) => query.trim().isEmpty
            ? const []
            : state.musicService.searchTracks(query),
      ),
    );
    if (picked == null) return;
    await state.resolveMissingTrack(entry, picked.id);
    _showMessage('"${picked.title}" associe.');
  }

  /// Relance le telechargement automatique existant (spotdl, recherche par
  /// artiste/titre -- voir DownloadWorkerService) puis propose a
  /// l'utilisateur de confirmer que le resultat est bien le bon titre avant
  /// de l'associer, plutot que de l'accepter les yeux fermes.
  Future<void> _autoDownload(Map<String, dynamic> entry) async {
    final state = context.read<AppState>();
    final worker = DownloadWorkerService();
    if (!worker.isConfigured) {
      _showMessage('Service de telechargement non configure.');
      return;
    }

    setState(() => _downloading.add(entry));
    try {
      final beforeIds = state.musicService.allTracks.map((t) => t.id).toSet();
      final album = (entry['album'] ?? '').toString();
      final jobId = await worker.requestDownload(
        artist: (entry['artist'] ?? '').toString(),
        title: (entry['title'] ?? '').toString(),
        album: album.isEmpty ? null : album,
      );
      if (jobId == null) {
        _showMessage('Impossible de lancer le telechargement.');
        return;
      }

      final status = await worker.waitForCompletion(jobId);
      if (status.state != DownloadJobState.done) {
        _showMessage(status.error ?? 'Echec du telechargement.');
        return;
      }

      // Diff avant/apres plutot qu'un re-matching flou sur le titre : le
      // fichier vient tout juste d'etre ecrit sur le NAS, donc tout titre
      // qu'on n'avait pas avant syncRecentlyAdded() est quasi-certainement
      // celui-la.
      await state.syncRecentlyAdded();
      final candidates = state.musicService.allTracks
          .where((t) => !beforeIds.contains(t.id))
          .toList();
      if (candidates.isEmpty) {
        _showMessage(
            'Telecharge, mais pas encore visible dans la bibliotheque -- reessaie dans un instant.');
        return;
      }
      if (!mounted) return;

      final picked = candidates.length == 1
          ? await _confirmCandidate(candidates.first)
          : await showModalBottomSheet<Track>(
              context: context,
              isScrollControlled: true,
              backgroundColor: const Color(0xFF1E1E1E),
              builder: (_) => _TrackPickerSheet(
                title: 'Lequel de ces titres est le bon ?',
                search: (_) => candidates,
              ),
            );
      if (picked == null) {
        _showMessage(
            'Telecharge mais pas associe -- retrouvable via l\'association manuelle.');
        return;
      }
      if (!mounted) return;
      await context.read<AppState>().resolveMissingTrack(entry, picked.id);
      _showMessage('"${picked.title}" associe.');
    } finally {
      if (mounted) setState(() => _downloading.remove(entry));
    }
  }

  Future<Track?> _confirmCandidate(Track candidate) {
    return showDialog<Track>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Est-ce le bon titre ?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          '${candidate.title}\n${candidate.artist} • ${candidate.album}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Non', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, candidate),
            child:
                const Text('Oui', style: TextStyle(color: Color(0xFF1DB954))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        final missing = state.missingTracks;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => state.popOverlay(),
            ),
            title: const Text('Titres manquants',
                style: TextStyle(color: Colors.white)),
            actions: [
              if (missing.isNotEmpty)
                TextButton(
                  onPressed: () {
                    state.clearMissingTracks();
                    state.popOverlay();
                  },
                  child: const Text('Effacer',
                      style: TextStyle(color: Colors.red)),
                ),
            ],
          ),
          body: missing.isEmpty
              ? const Center(
                  child: Text(
                    'Aucun titre manquant',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                      16, 16, 16, bottomBarReserve(context)),
                  itemCount: missing.length,
                  itemBuilder: (context, index) {
                    final track = missing[index];
                    final isDownloading = _downloading.contains(track);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.orange.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.music_note,
                              color: Colors.orange,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track['title'] ?? '',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${track['artist'] ?? ''} • ${track['album'] ?? ''}',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (isDownloading)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          else ...[
                            IconButton(
                              icon: const Icon(Icons.search,
                                  color: Colors.white54, size: 20),
                              tooltip: 'Associer manuellement',
                              onPressed: () => _associateManually(track),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cloud_download,
                                  color: Colors.white54, size: 20),
                              tooltip: 'Telecharger automatiquement',
                              onPressed: () => _autoDownload(track),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// Feuille de recherche/selection d'un titre : soit une recherche live dans
/// toute la bibliotheque (association manuelle), soit une liste fixe de
/// candidats deja connus (choix parmi les titres tout juste telecharges,
/// [search] ignore alors la requete tapee).
class _TrackPickerSheet extends StatefulWidget {
  final String title;
  final List<Track> Function(String query) search;
  final String initialQuery;

  const _TrackPickerSheet({
    required this.title,
    required this.search,
    this.initialQuery = '',
  });

  @override
  State<_TrackPickerSheet> createState() => _TrackPickerSheetState();
}

class _TrackPickerSheetState extends State<_TrackPickerSheet> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  late List<Track> _results = widget.search(widget.initialQuery);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Titre, artiste...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) =>
                    setState(() => _results = widget.search(value)),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _results.isEmpty
                    ? const Center(
                        child: Text('Aucun resultat',
                            style: TextStyle(color: Colors.white38)),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final track = _results[index];
                          return TrackTile(
                            track: track,
                            onTap: () => Navigator.of(context).pop(track),
                            // Purement informatif ici (deja like ou non) :
                            // pas question de toggler un like depuis ce
                            // picker, juste de choisir a quel titre associer
                            // l'entree manquante.
                            onLike: () {},
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
