import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/app_state.dart';

/// Telechargement / suppression hors-ligne partages par le bouton des
/// ecrans mobiles (DownloadButton) et les menus du PC.

/// Telecharge [tracks] (et suit [collection] si fournie : ses nouveaux
/// titres seront telecharges a chaque synchro), puis dit ce qu'il en est.
Future<void> downloadForOffline(
  BuildContext context, {
  required List<Track> tracks,
  String? collection,
  void Function(double progress)? onProgress,
}) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final playable = tracks.where((t) => !t.isPlaceholder).toList();
  if (playable.isEmpty) return;
  // Serveur injoignable (le « Mode hors-ligne » choisi, lui, n'empeche
  // pas de telecharger : c'est justement le moment, sur le Wi-Fi).
  if (state.isServerUnreachable) {
    messenger?.showSnackBar(const SnackBar(
        content: Text('Hors ligne : le téléchargement reprendra '
            'quand le serveur sera de nouveau joignable.')));
    if (collection != null) {
      // Suivie quand meme : la prochaine synchro la telechargera.
      await state.downloadCollection(collection, const []);
    }
    return;
  }
  final failed = collection == null
      ? await state.downloadTracksOffline(playable, onProgress: onProgress)
      : await state.downloadCollection(collection, playable,
          onProgress: onProgress);
  final ok = playable.length - failed;
  messenger?.showSnackBar(SnackBar(
    content: Text(failed == 0
        ? '${_titles(ok)} disponible${ok > 1 ? 's' : ''} hors connexion'
        : '${_titles(failed)} n\'${failed > 1 ? 'ont' : 'a'} pas pu être '
            'téléchargé${failed > 1 ? 's' : ''} (serveur injoignable ?)'),
  ));
}

String _titles(int n) => '$n titre${n > 1 ? 's' : ''}';

/// Demande confirmation puis supprime le telechargement.
Future<bool> removeOfflineDownload(
  BuildContext context, {
  required List<Track> tracks,
  String? collection,
  String message = 'Ce contenu ne sera plus disponible hors connexion.',
}) async {
  final state = context.read<AppState>();
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Supprimer le téléchargement',
          style: TextStyle(color: Colors.white)),
      content: Text(message, style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  if (confirm != true) return false;
  if (collection != null) {
    await state.removeCollection(collection, tracks);
  } else {
    await state.removeDownloads(tracks);
  }
  return true;
}

/// Vrai si tout est deja telecharge (ou, pour une collection vide suivie,
/// si elle est suivie).
bool isDownloadedForOffline(AppState state, List<Track> tracks,
    {String? collection}) {
  final playable = tracks.where((t) => !t.isPlaceholder).toList();
  if (playable.isEmpty) {
    return collection != null && state.isCollectionOffline(collection);
  }
  return state.areTracksOffline(playable);
}
