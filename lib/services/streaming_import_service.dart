import 'dart:convert';
import 'dart:io';

class StreamingImportService {
  // ===================== CSV STREAMING =====================

  static Stream<Map<String, String>> parseCsvStream(String filePath) async* {
    final file = File(filePath);
    final stream = file.openRead();
    var buffer = '';
    var isFirstLine = true;
    List<String>? headers;

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk, allowMalformed: true);

      var lineEnd = buffer.indexOf('\n');
      while (lineEnd != -1) {
        final line = buffer.substring(0, lineEnd).trim();
        buffer = buffer.substring(lineEnd + 1);

        if (line.isEmpty) {
          lineEnd = buffer.indexOf('\n');
          continue;
        }

        if (isFirstLine) {
          headers = _parseCsvLine(line);
          print('HEADERS PARSÉS: $headers');
          isFirstLine = false;
          lineEnd = buffer.indexOf('\n');
          continue;
        }

        if (headers != null) {
          final result = _parseCsvLineWithHeaders(line, headers);
          if (result['title']?.isNotEmpty == true) {
            yield result;
          }
        }

        lineEnd = buffer.indexOf('\n');
      }
    }

    if (buffer.trim().isNotEmpty && headers != null) {
      final result = _parseCsvLineWithHeaders(buffer.trim(), headers);
      if (result['title']?.isNotEmpty == true) {
        yield result;
      }
    }
  }

  static Map<String, String> _parseCsvLineWithHeaders(
      String line, List<String> headers) {
    final cols = _parseCsvLine(line);
    final headerLower = headers.map((h) => h.toLowerCase().trim()).toList();

    // Pour Exportify: Track URI, Track Name, Album Name, Artist Name(s), ...
    // Indices fixes connus si headers standards
    final titleIdx = _findIndexInList(headerLower,
        ['track name', 'title', 'name', 'track', 'song', 'titre', 'nom']);
    final artistIdx = _findIndexInList(headerLower, [
      'artist name(s)',
      'artist',
      'artists',
      'artist name',
      'artiste',
      'primary artist'
    ]);
    final albumIdx = _findIndexInList(headerLower,
        ['album name', 'album', 'album title', 'album_name', 'album_title']);
    final dateIdx = _findIndexInList(headerLower, [
      'added at',
      'date',
      'date added',
      'added_at',
      'date d\'ajout',
      'ajout',
      'timestamp',
      'dateadded'
    ]);

    print(
        'INDICES: title=$titleIdx, artist=$artistIdx, album=$albumIdx, date=$dateIdx');
    print('LIGNE: $cols');

    return {
      'title':
          titleIdx >= 0 && titleIdx < cols.length ? cols[titleIdx].trim() : '',
      'artist': artistIdx >= 0 && artistIdx < cols.length
          ? cols[artistIdx].trim().split(';').first.trim()
          : '',
      'album':
          albumIdx >= 0 && albumIdx < cols.length ? cols[albumIdx].trim() : '',
      'dateAdded':
          dateIdx >= 0 && dateIdx < cols.length ? cols[dateIdx].trim() : '',
    };
  }

  static int _findIndexInList(List<String> list, List<String> keywords) {
    for (var i = 0; i < list.length; i++) {
      final clean = list[i].replaceAll(RegExp(r'[^\w\s]'), '').trim();
      for (final kw in keywords) {
        if (clean == kw || clean.contains(kw)) return i;
      }
    }
    return -1;
  }

  // ===================== JSON =====================

  static Future<List<Map<String, String>>> parseJsonFile(
      String filePath) async {
    final file = File(filePath);
    final content = jsonDecode(await file.readAsString());

    if (content is Map && content['tracks'] is List) {
      return (content['tracks'] as List)
          .map((t) => {
                'title': (t['name'] ?? t['track']?['name'] ?? '').toString(),
                'artist':
                    (t['artist'] ?? t['artists']?[0]?['name'] ?? '').toString(),
                'album': (t['album'] ?? t['album']?['name'] ?? '').toString(),
                'dateAdded': _parseDate(t['added_at'] ?? t['dateAdded']),
              })
          .where((t) => t['title']!.isNotEmpty)
          .toList();
    }

    if (content is Map && content['items'] is List) {
      return (content['items'] as List)
          .map((item) {
            final track = item['track'] ?? item;
            final artists = track['artists'] as List? ?? [];
            return {
              'title': (track['name'] ?? '').toString(),
              'artist': artists.isNotEmpty ? artists[0]['name'].toString() : '',
              'album': (track['album']?['name'] ?? '').toString(),
              'dateAdded': _parseDate(item['added_at'] ?? item['dateAdded']),
            };
          })
          .where((t) => t['title']!.isNotEmpty)
          .toList();
    }

    if (content is List) {
      return content
          .map((item) => {
                'title': (item['title'] ?? '').toString(),
                'artist': (item['artist'] ?? '').toString(),
                'album': (item['album'] ?? '').toString(),
                'dateAdded': _parseDate(item['dateAdded'] ?? item['timestamp']),
              })
          .where((t) => t['title']!.isNotEmpty)
          .toList();
    }

    if (content is Map && content['content'] is List) {
      return (content['content'] as List)
          .map((item) => {
                'title': (item['title'] ?? '').toString(),
                'artist': (item['artist'] ?? '').toString(),
                'album': (item['album'] ?? '').toString(),
                'dateAdded': _parseDate(item['dateAdded'] ?? item['timestamp']),
              })
          .where((t) => t['title']!.isNotEmpty)
          .toList();
    }

    return [];
  }

  // ===================== UTILITAIRES =====================

  static String _parseDate(dynamic dateValue) {
    if (dateValue == null) return '';
    if (dateValue is String) {
      if (dateValue.contains('T')) {
        try {
          final dt = DateTime.parse(dateValue);
          return dt.toIso8601String().split('T')[0];
        } catch (_) {}
      }
      if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(dateValue)) {
        return dateValue.substring(0, 10);
      }
      return dateValue;
    }
    return '';
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

  static String get csvTemplate => 'title,artist,album,dateAdded\n'
      'Bohemian Rhapsody,Queen,A Night at the Opera,2024-03-15\n'
      'Hotel California,Eagles,Hotel California,2024-01-20\n'
      'Imagine,John Lennon,Imagine,2023-12-01\n'
      'Smells Like Teen Spirit,Nirvana,Nevermind,2024-02-10\n'
      'Billie Jean,Michael Jackson,Thriller,2023-11-15\n';
}
