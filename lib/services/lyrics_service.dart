import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/lyrics.dart';
import '../models/track.dart';

/// Trouve les paroles d'un titre : d'abord celles de Navidrome (tags du
/// fichier ou `.lrc` a cote, sur le NAS), sinon LRCLIB (base libre de
/// paroles synchronisees, sans cle d'API). Des paroles synchronisees sont
/// toujours preferees a du texte simple, quelle que soit la source.
///
/// Les reponses (y compris « rien trouve ») sont gardees en memoire le temps
/// de la session : rouvrir les paroles ne refait aucun appel.
class LyricsService {
  LyricsService({
    required Future<List<Map<String, dynamic>>> Function(String trackId)
        navidromeLyrics,
    http.Client? client,
  })  : _navidromeLyrics = navidromeLyrics,
        _client = client ?? http.Client();

  final Future<List<Map<String, dynamic>>> Function(String trackId)
      _navidromeLyrics;
  final http.Client _client;
  final _cache = <String, Future<Lyrics?>>{};

  static const lrclibHost = 'lrclib.net';

  /// Paroles de [track], ou null si aucune source n'en a.
  Future<Lyrics?> lyricsFor(Track track) {
    return _cache[track.id] ??= _find(track).then((result) {
      final (found, failed) = result;
      // Un echec reseau ne doit pas etre retenu comme « pas de paroles ».
      if (found == null && failed) _cache.remove(track.id);
      return found;
    });
  }

  /// (paroles, echec reseau de LRCLIB).
  Future<(Lyrics?, bool)> _find(Track track) async {
    Lyrics? plain;
    if (track.subsonicId != null) {
      final fromNas = fromStructured(await _navidromeLyrics(track.id));
      if (fromNas != null && fromNas.isSynced) return (fromNas, false);
      plain = fromNas;
    }
    final (fromLrclib, failed) = await _lrclib(track);
    if (fromLrclib != null && (fromLrclib.isSynced || plain == null)) {
      return (fromLrclib, false);
    }
    return (plain, failed && plain == null);
  }

  /// Paroles a partir de la reponse OpenSubsonic `structuredLyrics` : la
  /// premiere entree synchronisee, sinon la premiere tout court.
  static Lyrics? fromStructured(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return null;
    final entry = entries.firstWhere((e) => e['synced'] == true,
        orElse: () => entries.first);
    final synced = entry['synced'] == true;
    final offset = (entry['offset'] as num?)?.toInt() ?? 0;
    final raw = entry['line'];
    final lines = <LyricLine>[
      for (final l in raw is List ? raw : [raw])
        if (l is Map)
          LyricLine(
            (l['value'] ?? '').toString().trim(),
            start: synced && l['start'] is num
                ? Duration(
                    milliseconds: ((l['start'] as num).toInt() - offset)
                        .clamp(0, 1 << 31))
                : null,
          ),
    ];
    final lyrics = Lyrics(lines, source: 'Navidrome');
    return lyrics.isEmpty ? null : lyrics;
  }

  Future<(Lyrics?, bool)> _lrclib(Track track) async {
    final params = {
      'track_name': track.title,
      'artist_name': track.artist,
      if (track.album.isNotEmpty) 'album_name': track.album,
      if (track.duration.inSeconds > 0)
        'duration': '${track.duration.inSeconds}',
    };
    try {
      final response = await _client
          .get(Uri.https(lrclibHost, '/api/get', params), headers: const {
        'User-Agent': 'Vinland (lecteur personnel)'
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode == 404) return (null, false);
      if (response.statusCode != 200) return (null, true);
      return (
        fromLrclibJson(jsonDecode(utf8.decode(response.bodyBytes))),
        false
      );
    } catch (e) {
      debugPrint('LyricsService.lrclib(${track.title}): $e');
      return (null, true);
    }
  }

  /// Paroles d'une reponse LRCLIB (`syncedLyrics` au format LRC, sinon
  /// `plainLyrics`). Null pour un titre instrumental ou sans paroles.
  static Lyrics? fromLrclibJson(Object? json) {
    if (json is! Map || json['instrumental'] == true) return null;
    final synced = json['syncedLyrics'];
    if (synced is String && synced.trim().isNotEmpty) {
      final lyrics = Lyrics.parseLrc(synced, source: 'LRCLIB');
      if (!lyrics.isEmpty) return lyrics;
    }
    final plain = json['plainLyrics'];
    if (plain is String && plain.trim().isNotEmpty) {
      return Lyrics.plain(plain, source: 'LRCLIB');
    }
    return null;
  }
}
