import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/listening_stats.dart';

/// Journal d'ecoute d'un compte sur cet appareil : une ligne JSON par
/// ecoute, ajoutee en fin de fichier (`plays_<compte>.jsonl`, a cote des
/// donnees perso). Sert au bilan de l'annee (ListeningStats).
///
/// Ajout seul, jamais de reecriture : l'entree Bluetooth en arriere-plan
/// (autre isolate) peut ecrire en meme temps sans effacer les lignes de
/// l'app, et une coupure pendant l'ecriture n'abime que la derniere ligne,
/// sautee a la lecture.
class ListeningLog {
  ListeningLog(this.path);

  final String path;

  Future<void> append(PlayEvent event) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString('${jsonEncode(event.toJson())}\n',
          mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('ListeningLog.append: $e');
    }
  }

  /// Toutes les ecoutes, dans l'ordre du fichier. [] si le journal n'existe
  /// pas encore.
  Future<List<PlayEvent>> readAll() async {
    final file = File(path);
    if (!await file.exists()) return const [];
    try {
      return parse(await file.readAsString());
    } catch (e) {
      debugPrint('ListeningLog.readAll: $e');
      return const [];
    }
  }

  @visibleForTesting
  static List<PlayEvent> parse(String content) {
    final events = <PlayEvent>[];
    for (final line in const LineSplitter().convert(content)) {
      if (line.trim().isEmpty) continue;
      try {
        final event = PlayEvent.fromJson(jsonDecode(line));
        if (event != null) events.add(event);
      } on FormatException {
        // Ligne coupee par un arret brutal : on l'ignore.
      }
    }
    return events;
  }
}
