import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/lastfm_config.dart';
import '../models/track.dart';
import 'matching_service.dart';

/// Moods « humeur » (triste, joyeux...) : les tags Last.fm, que le genre
/// des fichiers ne donne pas. Seule l'API publique en lecture est utilisee
/// (tag.getTopTracks), avec la cle de lib/config/lastfm_config.dart.
class LastfmService {
  LastfmService({http.Client? client, String apiKey = kLastfmApiKey})
      : _client = client ?? http.Client(),
        _apiKey = apiKey;

  final http.Client _client;
  final String _apiKey;

  bool get isConfigured => _apiKey.isNotEmpty;

  /// Titres les plus associes au tag [tag] sur Last.fm, (artiste, titre).
  /// [] si pas de cle, pas de reseau ou reponse inattendue.
  Future<List<(String, String)>> topTracksForTag(String tag,
      {int limit = 300}) async {
    if (!isConfigured) return const [];
    final uri = Uri.https('ws.audioscrobbler.com', '/2.0/', {
      'method': 'tag.gettoptracks',
      'tag': tag,
      'limit': '$limit',
      'api_key': _apiKey,
      'format': 'json',
    });
    try {
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const [];
      final tracks =
          (jsonDecode(response.body)['tracks']?['track'] as List?) ?? const [];
      return [
        for (final t in tracks)
          if (t is Map && t['name'] != null && t['artist']?['name'] != null)
            (t['artist']['name'].toString(), t['name'].toString())
      ];
    } catch (e) {
      debugPrint('LastfmService.topTracksForTag($tag): $e');
      return const [];
    }
  }
}

/// Titres de [library] presents dans [candidates] (artiste, titre), par
/// titre normalise puis artiste (MatchingService) -- index par titre pour
/// ne pas comparer chaque candidat a toute la bibliotheque.
List<Track> matchInLibrary(
    List<(String, String)> candidates, List<Track> library) {
  final byTitle = <String, List<Track>>{};
  for (final t in library) {
    if (t.isPlaceholder) continue;
    byTitle
        .putIfAbsent(
            MatchingService.normalize(MatchingService.coreTitle(t.title)),
            () => [])
        .add(t);
  }
  final found = <String, Track>{};
  for (final (artist, title) in candidates) {
    final key = MatchingService.normalize(MatchingService.coreTitle(title));
    for (final t in byTitle[key] ?? const <Track>[]) {
      if (MatchingService.artistsMatch(t.artist, artist)) found[t.id] = t;
    }
  }
  return found.values.toList();
}
