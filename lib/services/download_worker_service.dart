import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/download_worker_config.dart';

/// Statut d'un job de telechargement, tel que renvoye par
/// GET /downloads/<job_id> (voir download-worker/server.py).
enum DownloadJobState { queued, running, done, failed, unknown }

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
}
