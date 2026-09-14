import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/app_state.dart';
import '../services/download_worker_service.dart';

/// Icone de fin de ligne pour un titre non possede localement (album,
/// artiste...) : cloud barre simple si le service de telechargement
/// automatique n'est pas configure, sinon bouton de requete de
/// telechargement avec ses propres etats (en cours/echec) -- partagee par
/// tous les ecrans qui listent ce genre de titre plutot que reimplementee
/// a chaque fois.
class DownloadStateIcon extends StatelessWidget {
  final DownloadUiState? state;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;
  final double size;

  const DownloadStateIcon({
    super.key,
    required this.state,
    required this.showDownloadButton,
    required this.onDownloadTap,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    if (state == DownloadUiState.downloading) {
      return SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(
            strokeWidth: 2, color: Colors.white38),
      );
    }
    if (showDownloadButton) {
      return InkWell(
        onTap: onDownloadTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            state == DownloadUiState.failed
                ? Icons.error_outline
                : Icons.download_rounded,
            color:
                state == DownloadUiState.failed ? Colors.redAccent : Colors.white54,
            size: size,
          ),
        ),
      );
    }
    return Icon(Icons.cloud_off, color: Colors.white24, size: size);
  }
}

/// Bouton de telechargement hors-ligne reutilisable (album, playlist,
/// titres likes...). Gere lui-meme son etat de progression et le dialogue
/// de confirmation de suppression.
class DownloadButton extends StatefulWidget {
  final List<Track> tracks;
  final String confirmDeleteMessage;
  final Color idleColor;

  const DownloadButton({
    super.key,
    required this.tracks,
    this.confirmDeleteMessage =
        'Ce contenu ne sera plus disponible hors connexion.',
    this.idleColor = Colors.white70,
  });

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  bool _downloading = false;
  double _progress = 0;

  Future<void> _toggle(AppState state) async {
    if (widget.tracks.isEmpty || _downloading) return;

    if (state.areTracksOffline(widget.tracks)) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Supprimer le telechargement',
              style: TextStyle(color: Colors.white)),
          content: Text(widget.confirmDeleteMessage,
              style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Supprimer', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await state.removeDownloads(widget.tracks);
        if (mounted) setState(() {});
      }
      return;
    }

    setState(() {
      _downloading = true;
      _progress = 0;
    });
    await state.downloadTracksOffline(widget.tracks, onProgress: (p) {
      if (mounted) setState(() => _progress = p);
    });
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (_downloading) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            value: _progress,
            strokeWidth: 2,
            color: const Color(0xFF1DB954),
          ),
        ),
      );
    }

    final downloaded = state.areTracksOffline(widget.tracks);
    return IconButton(
      icon: Icon(
        downloaded ? Icons.download_done : Icons.download_outlined,
        color: downloaded ? const Color(0xFF1DB954) : widget.idleColor,
      ),
      onPressed: widget.tracks.isEmpty ? null : () => _toggle(state),
    );
  }
}
