import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/discovered_artist.dart';
import '../models/discovered_album.dart';
import '../models/discovered_track.dart';
import '../models/track.dart';
import 'music_service.dart';

class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  factory DiscoveryService() => _instance;
  DiscoveryService._internal();

  final String _baseUrl = 'https://api.deezer.com';
  final MusicService _music = MusicService();

  Future<List<DiscoveredArtist>> searchArtists(String query,
      {int limit = 10}) async {
    if (query.trim().isEmpty) return [];
    final data = await _get('/search/artist', {'q': query, 'limit': '$limit'});
    final list = data['data'] as List? ?? [];
    final artists = list.map((j) => DiscoveredArtist.fromJson(j)).toList();
    artists.sort((a, b) => (b.nbFans ?? 0).compareTo(a.nbFans ?? 0));
    return artists;
  }

  Future<List<DiscoveredAlbum>> searchAlbums(String query,
      {int limit = 10}) async {
    if (query.trim().isEmpty) return [];
    final data = await _get('/search/album', {'q': query, 'limit': '$limit'});
    final list = data['data'] as List? ?? [];
    final results = list.map((j) => DiscoveredAlbum.fromJson(j)).toList();
    await _markLibraryStatus(results);
    return results;
  }

  Future<List<DiscoveredTrack>> searchTracks(String query,
      {int limit = 10}) async {
    if (query.trim().isEmpty) return [];
    final data = await _get('/search/track', {'q': query, 'limit': '$limit'});
    final list = data['data'] as List? ?? [];
    final results = list.map((j) => DiscoveredTrack.fromJson(j)).toList();
    await _markTrackLibraryStatus(results);
    return results;
  }

  Future<DiscoveredArtist?> getArtist(int artistId) async {
    final data = await _get('/artist/$artistId', {});
    if (data.isEmpty || data.containsKey('error')) return null;
    return DiscoveredArtist.fromJson(data);
  }

  Future<List<DiscoveredTrack>> getArtistTopTracks(int artistId,
      {int limit = 5}) async {
    final data = await _get('/artist/$artistId/top', {'limit': '$limit'});
    final list = data['data'] as List? ?? [];
    return list.map((j) => DiscoveredTrack.fromJson(j)).toList();
  }

  Future<List<DiscoveredAlbum>> getArtistAlbums(int artistId,
      {int limit = 50}) async {
    final data = await _get('/artist/$artistId/albums', {'limit': '$limit'});
    final list = data['data'] as List? ?? [];
    final results = list.map((j) => DiscoveredAlbum.fromJson(j)).toList();
    await _markLibraryStatus(results);
    return results;
  }

  Future<List<DiscoveredTrack>> getAlbumTracks(int albumId) async {
    final data = await _get('/album/$albumId/tracks', {});
    final list = data['data'] as List? ?? [];
    final results = list.map((j) => DiscoveredTrack.fromJson(j)).toList();
    await _markTrackLibraryStatus(results);
    return results;
  }

  Future<DiscoveredAlbum?> getAlbum(int albumId) async {
    final data = await _get('/album/$albumId', {});
    if (data.isEmpty || data.containsKey('error')) return null;
    return DiscoveredAlbum.fromJson(data);
  }

  // ── LIBRARY STATUS ──

  Future<void> _markLibraryStatus(List<DiscoveredAlbum> albums) async {
    final localTracks = _music.allTracks;
    final localAlbums = _music.albums;

    // Index : artiste normalisé → liste de tracks locales
    final tracksByArtist = <String, List<Track>>{};
    for (final t in localTracks) {
      final artist = _normalize(t.artist);
      tracksByArtist.putIfAbsent(artist, () => []).add(t);
    }

    for (final album in albums) {
      final normalizedArtist = _normalize(album.artistName);
      final normalizedTitle = _normalize(album.title);

      // 1. Match par nom d'album local
      album.isInLibrary = localAlbums.any((a) {
        return _artistsMatch(_normalize(a.artist), normalizedArtist) &&
            _albumsMatch(_normalize(a.title), normalizedTitle);
      });

      // 2. Fallback : match par tracks locales (même nom d'album approximatif)
      if (!album.isInLibrary) {
        final artistTracks = tracksByArtist[normalizedArtist] ?? [];
        // Regroupe les tracks locales par nom d'album
        final localAlbumNames = <String>{};
        for (final t in artistTracks) {
          localAlbumNames.add(_normalize(t.album));
        }
        album.isInLibrary = localAlbumNames.any((name) {
          return _albumsMatch(name, normalizedTitle);
        });
      }
    }
  }

  Future<void> _markTrackLibraryStatus(List<DiscoveredTrack> tracks) async {
    final localTracks = _music.allTracks;

    for (final track in tracks) {
      final normalizedArtist = _normalize(track.artistName);
      final normalizedTitle = _normalize(track.title);
      final normalizedAlbum = _normalize(track.albumName);

      track.isInLibrary = localTracks.any((t) {
        return _artistsMatch(_normalize(t.artist), normalizedArtist) &&
            _albumsMatch(_normalize(t.album), normalizedAlbum) &&
            _titlesMatch(_normalize(t.title), normalizedTitle);
      });
    }
  }

  /// Deep match : charge les tracks d'un album Deezer et compare avec les tracks locales.
  /// Retourne true si au moins [minMatchRatio] des tracks existent dans le NAS.
  Future<bool> deepMatchAlbum(DiscoveredAlbum album,
      {double minMatchRatio = 0.25}) async {
    if (album.isInLibrary) return true;

    final deezerTracks = await getAlbumTracks(album.id);
    if (deezerTracks.isEmpty) return false;

    final localTracks = _music.allTracks.where((t) {
      return _artistsMatch(_normalize(t.artist), _normalize(album.artistName));
    }).toList();

    int matches = 0;
    for (final dt in deezerTracks) {
      final dtTitle = _normalize(dt.title);
      if (localTracks
          .any((lt) => _titlesMatch(_normalize(lt.title), dtTitle))) {
        matches++;
      }
    }

    return matches / deezerTracks.length >= minMatchRatio;
  }

  // ── MATCHING LOGIC ──

  bool _artistsMatch(String a, String b) {
    if (a == b) return true;
    if (a.isEmpty || b.isEmpty) return false;
    if (a.contains(b) || b.contains(a)) return true;

    final partsA = a
        .split(RegExp(r'[/&,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final partsB = b
        .split(RegExp(r'[/&,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    for (final pa in partsA) {
      for (final pb in partsB) {
        if (pa == pb || pa.contains(pb) || pb.contains(pa)) return true;
      }
    }
    return false;
  }

  bool _albumsMatch(String a, String b) {
    if (a == b) return true;
    if (a.isEmpty || b.isEmpty) return false;
    if (a.contains(b) || b.contains(a)) return true;

    final coreA = _extractCoreTitle(a);
    final coreB = _extractCoreTitle(b);

    if (coreA == coreB) return true;
    if (coreA.isEmpty || coreB.isEmpty) return false;
    if (coreA.contains(coreB) || coreB.contains(coreA)) return true;

    return _similarity(a, b) > 0.50;
  }

  bool _titlesMatch(String a, String b) {
    if (a == b) return true;
    if (a.contains(b) || b.contains(a)) return true;
    return _similarity(a, b) > 0.70;
  }

  String _extractCoreTitle(String title) {
    var core = title.toLowerCase();
    core = core.replaceAll(
        RegExp(
            r'^(vol\.?|volume|season|part|act|episode|ep)\s*\d*\s*[:\-–—]\s*'),
        '');
    core = core.replaceAll(RegExp(r'\(.*?\)'), '');
    core = core.replaceAll(
        RegExp(
            r'\b(original|soundtrack|score|music|from|the|series|animated|of|ost|motion|picture)\b'),
        '');
    return _normalize(core);
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1.0;
    final dist = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    return 1.0 - (dist / maxLen);
  }

  int _levenshtein(String a, String b) {
    final matrix = List.generate(
      a.length + 1,
      (i) => List.filled(b.length + 1, 0),
    );
    for (var i = 0; i <= a.length; i++) matrix[i][0] = i;
    for (var j = 0; j <= b.length; j++) matrix[0][j] = j;
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
    }
    return matrix[a.length][b.length];
  }

  Future<Map<String, dynamic>> _get(
      String endpoint, Map<String, String> params) async {
    final uri =
        Uri.parse('$_baseUrl$endpoint').replace(queryParameters: params);
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('DiscoveryService error: $e');
    }
    return {};
  }
}
