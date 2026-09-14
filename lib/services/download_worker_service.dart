import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/download_worker_config.dart';

/// Statut d'un job de telechargement, tel que renvoye par
/// GET /downloads/<job_id> (voir download-worker/server.py).
enum DownloadJobState { queued, running, done, failed, unknown }

/// Etat d'affichage d'une ligne de titre non possede (album/artiste,
/// local ou decouverte) pendant une requete de telechargement -- partage
/// par tous les ecrans qui affichent l'icone "cloud_off" cliquable.
enum DownloadUiState { downloading, failed }

class DownloadJobStatus {
  final DownloadJobState state;
  final List<String> files;
  final String? error;

  const DownloadJobStatus({
    required this.state,
    this.files = const [],
    this.error,
  });

  factory DownloadJobStatus.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String?;
    final state = switch (status) {
      'queued' => DownloadJobState.queued,
      'running' => DownloadJobState.running,
      'done' => DownloadJobState.done,
      'failed' => DownloadJobState.failed,
      _ => DownloadJobState.unknown,
    };
    return DownloadJobStatus(
      state: state,
      files: (json['files'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      error: json['error']?.toString(),
    );
  }
}

/// Statut d'un fichier au sein d'un import local (voir POST /imports dans
/// download-worker/server.py) : song_id est l'id Subsonic retrouve apres
/// scan (prefixe 'navidrome_' pour matcher Track.id cote app), ou null si le
/// worker n'a pas reussi a le retrouver (tags illisibles, non trouve...).
class ImportedFile {
  final String originalFilename;
  final String? artist;
  final String? title;
  final String? songId;
  final bool matched;

  const ImportedFile({
    required this.originalFilename,
    this.artist,
    this.title,
    this.songId,
    required this.matched,
  });

  factory ImportedFile.fromJson(Map<String, dynamic> json) => ImportedFile(
        originalFilename: json['original_filename']?.toString() ?? '',
        artist: json['artist']?.toString(),
        title: json['title']?.toString(),
        songId: json['song_id']?.toString(),
        matched: json['matched'] == true,
      );

  /// Id au format Track.id ('navidrome_<id>'), voir NavidromeService.
  String? get trackId => songId == null ? null : 'navidrome_$songId';
}

class ImportJobStatus {
  final DownloadJobState state;
  final List<ImportedFile> files;

  const ImportJobStatus({required this.state, this.files = const []});

  factory ImportJobStatus.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String?;
    final state = switch (status) {
      'queued' => DownloadJobState.queued,
      'running' => DownloadJobState.running,
      'done' => DownloadJobState.done,
      'failed' => DownloadJobState.failed,
      _ => DownloadJobState.unknown,
    };
    return ImportJobStatus(
      state: state,
      files: (json['files'] as List?)
              ?.map((e) => ImportedFile.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

/// Resultat d'un AppState.importLocalFilesToPlaylist : combien de morceaux
/// ont rejoint la playlist, et lesquels le worker n'a pas reussi a
/// retrouver dans Navidrome apres le scan (a signaler a l'utilisateur).
class LocalImportResult {
  final int matchedCount;
  final List<String> unmatchedFilenames;
  final int duplicateSkippedCount;

  const LocalImportResult({
    required this.matchedCount,
    required this.unmatchedFilenames,
    this.duplicateSkippedCount = 0,
  });
}

/// Client du service de telechargement automatique (voir download-worker/ a
/// la racine du repo) : recoit "artiste - titre" pour un morceau trouve via
/// DiscoveryService (Deezer) mais absent du NAS, le telecharge et le range
/// dans la bibliotheque Navidrome partagee. Meme principe que AvatarService :
/// cle partagee cote config gitignoree, service maison fait le reste.
class DownloadWorkerService {
  bool get isConfigured => kDownloadWorkerServiceBaseUrl.isNotEmpty;

  Future<String?> requestDownload({
    required String artist,
    required String title,
    String? album,
  }) async {
    if (!isConfigured) {
      debugPrint('[DownloadWorker] isConfigured=false, base URL vide');
      return null;
    }
    final uri = Uri.parse('$kDownloadWorkerServiceBaseUrl/downloads');
    debugPrint('[DownloadWorker] POST $uri artist="$artist" title="$title"');
    try {
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-Api-Key': kDownloadWorkerServiceApiKey,
            },
            body: jsonEncode({
              'artist': artist,
              'title': title,
              if (album != null) 'album': album,
            }),
          )
          .timeout(const Duration(seconds: 15));
      debugPrint(
          '[DownloadWorker] POST -> ${response.statusCode} ${response.body}');
      if (response.statusCode != 202) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['job_id'] as String?;
    } catch (e) {
      debugPrint('[DownloadWorker] POST exception: $e');
      return null;
    }
  }

  Future<DownloadJobStatus?> getJobStatus(String jobId) async {
    if (!isConfigured) return null;
    final uri = Uri.parse('$kDownloadWorkerServiceBaseUrl/downloads/$jobId');
    try {
      final response = await http
          .get(uri, headers: {'X-Api-Key': kDownloadWorkerServiceApiKey})
          .timeout(const Duration(seconds: 15));
      debugPrint(
          '[DownloadWorker] GET $uri -> ${response.statusCode} ${response.body}');
      if (response.statusCode != 200) return null;
      return DownloadJobStatus.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('[DownloadWorker] GET exception: $e');
      return null;
    }
  }

  /// Interroge le job jusqu'a ce qu'il soit termine (done/failed), ou que
  /// [timeout] soit atteint. Doit rester superieur au DOWNLOAD_TIMEOUT_SECONDS
  /// cote serveur (defaut 300s) : sinon l'app abandonne et affiche un echec
  /// alors que le job continue normalement cote NAS.
  Future<DownloadJobStatus> waitForCompletion(
    String jobId, {
    Duration pollInterval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 6),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await getJobStatus(jobId);
      if (status == null) {
        return const DownloadJobStatus(
          state: DownloadJobState.failed,
          error: 'Service de telechargement injoignable',
        );
      }
      if (status.state == DownloadJobState.done ||
          status.state == DownloadJobState.failed) {
        return status;
      }
      await Future.delayed(pollInterval);
    }
    return const DownloadJobStatus(
      state: DownloadJobState.failed,
      error: 'Delai d\'attente depasse',
    );
  }

  /// Upload un ou plusieurs fichiers audio locaux (voir POST /imports) pour
  /// les integrer a la bibliotheque NAS. [files] doivent exister sur disque
  /// (chemins issus de file_picker en mode desktop/mobile, pas web).
  Future<String?> uploadImportFiles(List<File> files) async {
    if (!isConfigured || files.isEmpty) return null;
    final uri = Uri.parse('$kDownloadWorkerServiceBaseUrl/imports');
    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers['X-Api-Key'] = kDownloadWorkerServiceApiKey;
      for (final file in files) {
        request.files.add(await http.MultipartFile.fromPath('files', file.path));
      }
      final streamed = await request.send().timeout(const Duration(minutes: 10));
      final response = await http.Response.fromStream(streamed);
      debugPrint(
          '[DownloadWorker] POST $uri (${files.length} fichiers) -> ${response.statusCode}');
      if (response.statusCode != 202) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['job_id'] as String?;
    } catch (e) {
      debugPrint('[DownloadWorker] import upload exception: $e');
      return null;
    }
  }

  Future<ImportJobStatus?> getImportJobStatus(String jobId) async {
    if (!isConfigured) return null;
    final uri = Uri.parse('$kDownloadWorkerServiceBaseUrl/imports/$jobId');
    try {
      final response = await http
          .get(uri, headers: {'X-Api-Key': kDownloadWorkerServiceApiKey})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return ImportJobStatus.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('[DownloadWorker] import GET exception: $e');
      return null;
    }
  }

  /// Interroge le job d'import jusqu'a ce qu'il soit termine (done/failed),
  /// ou que [timeout] soit atteint -- un gros lot (musiques likees d'un ami)
  /// attend le scan Navidrome complet, donc un delai bien plus large que
  /// waitForCompletion().
  Future<ImportJobStatus> waitForImportCompletion(
    String jobId, {
    Duration pollInterval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await getImportJobStatus(jobId);
      if (status == null) {
        return const ImportJobStatus(state: DownloadJobState.failed);
      }
      if (status.state == DownloadJobState.done ||
          status.state == DownloadJobState.failed) {
        return status;
      }
      await Future.delayed(pollInterval);
    }
    return const ImportJobStatus(state: DownloadJobState.failed);
  }
}
