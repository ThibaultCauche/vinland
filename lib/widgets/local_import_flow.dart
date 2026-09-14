import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

/// Destination choisie pour un import de fichiers locaux vers le NAS :
/// une playlist (nouvelle ou existante), ou directement les titres likes --
/// au plus un des deux premiers champs est non-null, et [liked] est
/// mutuellement exclusif avec eux.
class LocalImportTarget {
  final String? existingPlaylistId;
  final String? newPlaylistName;
  final bool liked;

  const LocalImportTarget._({
    this.existingPlaylistId,
    this.newPlaylistName,
    this.liked = false,
  });

  factory LocalImportTarget.existing(String playlistId) =>
      LocalImportTarget._(existingPlaylistId: playlistId);

  factory LocalImportTarget.newPlaylist(String name) =>
      LocalImportTarget._(newPlaylistName: name);

  factory LocalImportTarget.liked() => const LocalImportTarget._(liked: true);
}

/// Demande une playlist destination (nouvelle ou existante), upload [files]
/// vers le NAS (AppState.importLocalFilesToPlaylist) avec une boite de
/// progression, puis affiche un resume. Partage entre l'ecran mobile
/// (ImportReviewScreen, apres la revue/edition des tags) et la bibliotheque
/// desktop (DesktopLibraryView, qui n'a pas cet ecran de revue) pour ne pas
/// dupliquer ce flux -- seul le mode de selection des fichiers differe entre
/// les deux plateformes.
///
/// Renvoie false si l'utilisateur a annule le choix de playlist (rien n'a
/// ete tente), true sinon (upload reussi ou non -- l'utilisateur a de toute
/// facon deja un message a l'ecran).
Future<bool> runLocalImportFlow(BuildContext context, List<File> files) async {
  if (files.isEmpty) return false;
  final state = context.read<AppState>();

  final target = await _pickPlaylistTarget(context, state);
  if (target == null || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      backgroundColor: Color(0xFF1E1E1E),
      content: Row(
        children: [
          CircularProgressIndicator(color: Color(0xFF1DB954)),
          SizedBox(width: 20),
          Expanded(
            child: Text(
              "Envoi vers le NAS et scan Navidrome...\nCa peut prendre plusieurs minutes pour un gros lot.",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );

  final result = await state.importLocalFiles(
    files: files,
    existingPlaylistId: target.existingPlaylistId,
    newPlaylistName: target.newPlaylistName,
    addToLiked: target.liked,
  );

  if (!context.mounted) return true;
  Navigator.of(context, rootNavigator: true).pop(); // ferme le dialog de progression

  if (result == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
            "Echec de l'import (NAS/service de telechargement injoignable)"),
        backgroundColor: Colors.red,
      ),
    );
    return true;
  }

  final destination = target.liked ? 'aux titres likes' : 'a la playlist';
  final parts = <String>['${result.matchedCount} titre(s) ajoute(s) $destination'];
  if (result.duplicateSkippedCount > 0) {
    parts.add(
        '${result.duplicateSkippedCount} deja dans ta bibliotheque (pas re-uploade)');
  }
  if (result.unmatchedFilenames.isNotEmpty) {
    parts.add('${result.unmatchedFilenames.length} introuvable(s) apres scan '
        '(${result.unmatchedFilenames.take(3).join(", ")}${result.unmatchedFilenames.length > 3 ? "..." : ""})');
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(parts.join(', ')),
      backgroundColor: const Color(0xFF1DB954),
      duration: const Duration(seconds: 6),
    ),
  );
  return true;
}

Future<LocalImportTarget?> _pickPlaylistTarget(
    BuildContext context, AppState state) {
  final playlists = state.playlists;
  return showModalBottomSheet<LocalImportTarget>(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Ou ajouter ces titres ?',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
          const Divider(color: Color(0xFF2A2A2A), height: 1),
          ListTile(
            leading: const Icon(Icons.favorite, color: Color(0xFF1DB954)),
            title: const Text('Titres likes',
                style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, LocalImportTarget.liked()),
          ),
          const Divider(color: Color(0xFF2A2A2A), height: 1),
          ListTile(
            leading: const Icon(Icons.playlist_add, color: Color(0xFF1DB954)),
            title: const Text('Nouvelle playlist',
                style: TextStyle(color: Colors.white)),
            onTap: () async {
              final controller = TextEditingController();
              final name = await showDialog<String>(
                context: ctx,
                builder: (dCtx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1E1E),
                  title: const Text('Nom de la playlist',
                      style: TextStyle(color: Colors.white)),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF2A2A2A)),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dCtx),
                      child: const Text('Annuler',
                          style: TextStyle(color: Colors.white54)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dCtx, controller.text),
                      child: const Text('Creer',
                          style: TextStyle(color: Color(0xFF1DB954))),
                    ),
                  ],
                ),
              );
              if (name != null && name.trim().isNotEmpty && ctx.mounted) {
                Navigator.pop(ctx, LocalImportTarget.newPlaylist(name.trim()));
              }
            },
          ),
          if (playlists.isNotEmpty)
            const Divider(color: Color(0xFF2A2A2A), height: 1),
          ...playlists.map((pl) => ListTile(
                leading:
                    const Icon(Icons.queue_music, color: Colors.white54),
                title: Text(pl.name,
                    style: const TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(ctx, LocalImportTarget.existing(pl.id)),
              )),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
