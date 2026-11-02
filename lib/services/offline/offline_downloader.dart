import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Telechargement d'un fichier pour l'ecoute hors-ligne, sans dependance a
/// la bibliotheque (testable avec un faux client HTTP).
///
/// Le flux est ecrit au fil de l'eau dans `<cible>.part`, puis renomme une
/// fois complet : un telechargement coupe (reseau, app tuee) ne laisse
/// jamais un fichier a moitie ecrit qui passerait pour un titre telecharge,
/// et un gros fichier ne passe plus entierement par la memoire.
class OfflineDownloader {
  OfflineDownloader({
    http.Client? client,
    this.timeout = const Duration(minutes: 3),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// Delai maximal pour un fichier entier.
  final Duration timeout;

  /// Telecharge [url] dans [target]. Vrai si le fichier est complet et non
  /// vide ; sinon rien n'est laisse sur le disque.
  Future<bool> fetchToFile(String url, File target) async {
    if (url.isEmpty) return false;
    final part = File('${target.path}.part');
    try {
      await target.parent.create(recursive: true);
      final response =
          await _client.send(http.Request('GET', Uri.parse(url))).timeout(
                timeout,
              );
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        return false;
      }
      // Navidrome repond 200 avec un JSON d'erreur Subsonic (titre
      // introuvable, jeton refuse) : ce n'est pas un fichier audio/image.
      final type = response.headers['content-type'] ?? '';
      if (type.contains('json') || type.contains('xml')) {
        await response.stream.drain<void>();
        return false;
      }
      final sink = part.openWrite();
      var bytes = 0;
      try {
        await response.stream
            .map((chunk) {
              bytes += chunk.length;
              return chunk;
            })
            .pipe(sink)
            .timeout(timeout);
      } catch (_) {
        await sink.close().catchError((_) {});
        rethrow;
      }
      if (bytes == 0) {
        await _deleteQuietly(part);
        return false;
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      return true;
    } catch (e) {
      debugPrint('OFFLINE: echec du telechargement : $e');
      await _deleteQuietly(part);
      return false;
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Nom de fichier sur pour un id (titre ou pochette) : un id Navidrome est
  /// deja alphanumerique, mais on ne fait confiance a rien de ce qui vient
  /// du serveur pour construire un chemin.
  static String safeFileName(String id) {
    final cleaned = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return cleaned.isEmpty ? '_' : cleaned;
  }

  /// Execute [task] sur chaque element, au plus [concurrency] a la fois.
  static Future<void> runPool<T>(
    List<T> items,
    int concurrency,
    Future<void> Function(T item) task,
  ) async {
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final item = items[next++];
        await task(item);
      }
    }

    final workers = concurrency.clamp(1, items.isEmpty ? 1 : items.length);
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  }
}
