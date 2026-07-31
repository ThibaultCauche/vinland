import 'dart:convert';
import 'dart:io';

class SpotifyImportService {
  /// Parse un fichier JSON exporté depuis SpotMyBackup ou l'API Spotify
  static List<Map<String, String>> parseJson(String filePath) {
    final file = File(filePath);
    final content = jsonDecode(file.readAsStringSync());

    // Format SpotMyBackup : {"tracks": [{"name": "...", "artist": "...", "album": "..."}]}
    if (content is Map && content['tracks'] is List) {
      return (content['tracks'] as List)
          .map((t) => {
                'title': (t['name'] ?? t['track']?['name'] ?? '').toString(),
                'artist':
                    (t['artist'] ?? t['artists']?[0]?['name'] ?? '').toString(),
                'album': (t['album'] ?? t['album']?['name'] ?? '').toString(),
              })
          .where((t) => t['title']!.isNotEmpty)
          .toList();
    }

    // Format API Spotify : {"items": [{"track": {"name": "...", "artists": [...], "album": {"name": "..."}}}]}
    if (content is Map && content['items'] is List) {
      return (content['items'] as List)
          .map((item) {
            final track = item['track'] ?? item;
            final artists = track['artists'] as List? ?? [];
            return {
              'title': (track['name'] ?? '').toString(),
              'artist': artists.isNotEmpty ? artists[0]['name'].toString() : '',
              'album': (track['album']?['name'] ?? '').toString(),
            };
          })
          .where((t) => t['title']!.isNotEmpty)
          .toList();
    }

    return [];
  }

  /// Parse un fichier CSV (export manuel)
  static List<Map<String, String>> parseCsv(String filePath) {
    final file = File(filePath);
    final lines = file.readAsLinesSync();
    if (lines.isEmpty) return [];

    final header = lines[0].toLowerCase();
    final titleIdx = _findIndex(header, ['title', 'name', 'track']);
    final artistIdx = _findIndex(header, ['artist', 'artists']);
    final albumIdx = _findIndex(header, ['album', 'album name']);

    final results = <Map<String, String>>[];
    for (var i = 1; i < lines.length; i++) {
      final cols = _parseCsvLine(lines[i]);
      if (cols.length > titleIdx && cols[titleIdx].trim().isNotEmpty) {
        results.add({
          'title': cols[titleIdx].trim(),
          'artist': artistIdx >= 0 && artistIdx < cols.length
              ? cols[artistIdx].trim()
              : '',
          'album': albumIdx >= 0 && albumIdx < cols.length
              ? cols[albumIdx].trim()
              : '',
        });
      }
    }
    return results;
  }

  static List<String> _parseCsvLine(String line) {
    final result = <String>[];
    var current = '';
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          current += '"';
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        result.add(current.trim());
        current = '';
      } else {
        current += char;
      }
    }
    result.add(current.trim());
    return result;
  }

  static int _findIndex(String header, List<String> keywords) {
    final parts = header.split(',');
    for (var i = 0; i < parts.length; i++) {
      for (final kw in keywords) {
        if (parts[i].trim().toLowerCase().contains(kw)) return i;
      }
    }
    return 0;
  }
}
