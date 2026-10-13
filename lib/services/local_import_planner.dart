import 'dart:io';

import 'package:metadata_god/metadata_god.dart';

import '../models/track.dart';
import 'matching_service.dart';

/// Preparation d'un import de fichiers audio locaux vers le NAS (voir
/// AppState.importLocalFiles) : reperage des doublons deja presents dans la
/// bibliotheque, puis decoupage en lots d'upload raisonnables.

// Taille max d'un lot d'upload : garde une marge confortable sous
// MAX_IMPORT_BODY_BYTES cote worker (500 Mo par defaut, voir
// services/download-worker/) pour ne jamais s'en approcher, et evite une
// seule requete HTTP de plusieurs centaines de Mo/Go pour un gros import
// (bibliotheque "titres likes" d'un ami) -- fragile (un seul hoquet reseau
// perd tout le lot) et gourmande en RAM cote NAS (le worker lit tout le
// corps de la requete en memoire).
const int importBatchMaxBytes = 150 * 1024 * 1024;
const int importBatchMaxFiles = 50;

typedef LocalTagReader = Future<(String artist, String title)?> Function(
    File file);

/// Lit (artiste, titre) depuis les tags locaux du fichier (MetadataGod,
/// meme lib que MusicService.parseFile), ou null si illisibles/absents. Pas
/// de repli sur le nom de fichier ici (contrairement au worker cote NAS) :
/// un faux-negatif se contente d'uploader normalement, alors qu'un
/// faux-positif sur un nom de fichier ambigu ferait sauter silencieusement
/// un vrai import.
Future<(String, String)?> readLocalTags(File file) async {
  try {
    final metadata = await MetadataGod.readMetadata(file: file.path);
    final artist = metadata.artist;
    final title = metadata.title;
    if (artist != null &&
        artist.isNotEmpty &&
        title != null &&
        title.isNotEmpty) {
      return (artist, title);
    }
  } catch (_) {
    // Tags illisibles -- traite comme "pas de dedup possible".
  }
  return null;
}

/// Separe [files] entre ceux deja presents dans [library] (tags locaux
/// correspondant a un Track deja synchronise, meme comparateur flou que
/// l'import CSV -- MatchingService) et ceux a effectivement uploader. Evite
/// de dupliquer un fichier deja sur le NAS (espace disque limite -- voir le
/// RAID1 de l'utilisateur, 1 To utilisable) au prix d'une lecture de tags
/// locale, sans appel reseau.
Future<(List<File> toUpload, List<String> alreadyPresentTrackIds)>
    splitAlreadyInLibrary(List<File> files, List<Track> library,
        {LocalTagReader readTags = readLocalTags}) async {
  final toUpload = <File>[];
  final alreadyPresentTrackIds = <String>[];
  for (final file in files) {
    final tags = await readTags(file);
    Track? existing;
    if (tags != null) {
      final (artist, title) = tags;
      for (final t in library) {
        if (MatchingService.titlesMatch(t.title, title) &&
            MatchingService.artistsMatch(t.artist, artist, strict: true)) {
          existing = t;
          break;
        }
      }
    }
    if (existing != null) {
      alreadyPresentTrackIds.add(existing.id);
    } else {
      toUpload.add(file);
    }
  }
  return (toUpload, alreadyPresentTrackIds);
}

/// Decoupe [files] en lots d'au plus [maxBytes] / [maxFiles] (ce qui vient
/// en premier), pour que chaque upload reste une requete HTTP raisonnable.
Future<List<List<File>>> batchFilesForImport(List<File> files,
    {int maxBytes = importBatchMaxBytes,
    int maxFiles = importBatchMaxFiles}) async {
  final batches = <List<File>>[];
  var current = <File>[];
  var currentBytes = 0;
  for (final file in files) {
    final size = await file.length();
    if (current.isNotEmpty &&
        (currentBytes + size > maxBytes || current.length >= maxFiles)) {
      batches.add(current);
      current = [];
      currentBytes = 0;
    }
    current.add(file);
    currentBytes += size;
  }
  if (current.isNotEmpty) batches.add(current);
  return batches;
}
