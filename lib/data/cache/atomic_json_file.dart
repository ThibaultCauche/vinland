import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Contenu relu par [AtomicJsonFile.read].
class JsonFileRead {
  JsonFileRead(this.data, this.raw, {required this.fromBackup});

  final Map<String, dynamic> data;

  /// Texte brut, pour les verifications qui ne passent pas par le JSON
  /// decode (ex. URL avec jeton d'un vieux cache) et pour mesurer la taille.
  final String raw;

  /// Vrai si le fichier principal etait absent ou illisible et que c'est la
  /// version precedente (`.bak`) qui a ete rechargee.
  final bool fromBackup;
}

/// Fichier JSON qui ne peut pas etre laisse a moitie ecrit.
///
/// Avant, le cache etait reecrit en place (`writeAsString`) : si Android
/// tuait l'app pendant l'ecriture, le fichier restait tronque, le
/// chargement suivant echouait en silence et l'app perdait les titres hors
/// ligne, les playlists locales et l'ordre des likes.
///
/// Maintenant chaque ecriture va dans un fichier temporaire du meme dossier
/// (meme volume, donc `rename` atomique), vide sur le disque (`flush`), puis
/// remplace le principal ; l'ancien principal devient `.bak`. A tout
/// instant il existe donc au moins une version complete sur le disque :
/// - tue pendant l'ecriture du temporaire : le principal n'a pas bouge ;
/// - tue entre les deux `rename` : le principal manque, `.bak` est complet.
class AtomicJsonFile {
  AtomicJsonFile._(this.path);

  /// Une seule instance par chemin dans le processus, pour que toutes les
  /// ecritures d'un meme fichier passent par la meme file d'attente.
  factory AtomicJsonFile(String path) =>
      _instances.putIfAbsent(path, () => AtomicJsonFile._(path));

  static final Map<String, AtomicJsonFile> _instances = {};

  final String path;

  /// Ecritures du processus mises a la queue : deux sauvegardes rapprochees
  /// (debounce + saveToCache explicite) ne se marchent jamais dessus.
  Future<void> _queue = Future.value();

  static int _tmpCounter = 0;

  File get _main => File(path);
  File get _backup => File('$path.bak');

  /// Copie d'un principal illisible, gardee pour comprendre ce qui s'est
  /// passe (jamais relue par l'app).
  File get _corrupt => File('$path.corrupt');

  /// Ecrit [data]. Le JSON est encode tout de suite : une modification de
  /// [data] apres l'appel n'a pas d'effet sur ce qui sera ecrit.
  Future<void> write(Map<String, dynamic> data) {
    final content = jsonEncode(data);
    final op = _queue.then((_) => _write(content));
    // Une ecriture ratee ne doit pas bloquer les suivantes.
    _queue = op.catchError((_) {});
    return op;
  }

  Future<void> _write(String content) async {
    await _main.parent.create(recursive: true);
    // Nom unique (pid + compteur) : l'entree Bluetooth en arriere-plan a sa
    // propre instance de MusicService dans un autre isolate, et ne partage
    // pas notre file d'attente.
    final tmp = File('$path.$pid.${_tmpCounter++}.tmp');
    try {
      final raf = await tmp.open(mode: FileMode.writeOnly);
      try {
        await raf.writeString(content);
        await raf.flush();
      } finally {
        await raf.close();
      }
      if (await _main.exists()) {
        await _main.rename(_backup.path);
      }
      await tmp.rename(path);
    } catch (e) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  /// Relit le fichier, ou sa version precedente si le principal est absent
  /// ou illisible. Null si aucune des deux n'est utilisable (premier
  /// lancement, ou les deux abimes).
  Future<JsonFileRead?> read() async {
    await _deleteStaleTemporaries();
    final main = await _tryRead(_main);
    if (main != null) return JsonFileRead(main.$1, main.$2, fromBackup: false);

    if (await _main.exists()) {
      debugPrint('CACHE ILLISIBLE: ${p.basename(path)}, copie dans .corrupt, '
          'repli sur la version precedente');
      try {
        await _main.copy(_corrupt.path);
      } catch (e) {
        debugPrint('CACHE: copie .corrupt impossible: $e');
      }
    }
    final backup = await _tryRead(_backup);
    if (backup != null) {
      debugPrint(
          'CACHE: version precedente rechargee pour ${p.basename(path)}');
      return JsonFileRead(backup.$1, backup.$2, fromBackup: true);
    }
    if (await _backup.exists()) {
      debugPrint(
          'CACHE: version precedente illisible aussi pour ${p.basename(path)}');
    }
    return null;
  }

  Future<(Map<String, dynamic>, String)?> _tryRead(File file) async {
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return (Map<String, dynamic>.from(decoded), raw);
    } catch (_) {
      return null;
    }
  }

  /// Temporaires laisses par une ecriture interrompue (app tuee avant le
  /// `rename`) : jamais relus, juste supprimes pour ne pas s'accumuler.
  /// Seulement les vieux : un temporaire recent peut etre en cours
  /// d'ecriture par l'autre isolate (entree Bluetooth).
  Future<void> _deleteStaleTemporaries() async {
    final dir = _main.parent;
    if (!await dir.exists()) return;
    final prefix = '${p.basename(path)}.';
    final cutoff = DateTime.now().subtract(staleTemporaryAge);
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith(prefix) || !name.endsWith('.tmp')) continue;
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {}
    }
  }

  @visibleForTesting
  static Duration staleTemporaryAge = const Duration(minutes: 1);
}
