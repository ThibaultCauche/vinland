import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/discovered_artist.dart';
import '../models/discovered_album.dart';
import '../models/discovered_track.dart';
import 'music_service.dart';

/// Service de découverte via l'API Deezer (pas de clé API requise).
/// Rate limit : ~50 requêtes / 5 secondes par IP.
class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  factory DiscoveryService() => _instance;
  DiscoveryService._internal();

  final String _baseUrl = 'https://api.deezer.com';
  final MusicService _music = MusicService();

  // ── RECHERCHE ──

  Future<List<DiscoveredArtist>> searchArtists(String query,
      {int limit = 10}) async {
    if (query.trim().isEmpty) return [];
    final data = await _get('/search/artist', {'q': query, 'limit': '$limit'});
    final list = data['data'] as List? ?? [];
    return list.map((j) => DiscoveredArtist.fromJson(j)).toList();
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

  // ── DÉTAILS ARTISTE ──

  Future<DiscoveredArtist?> getArtist(int artistId) async {
    final data = await _get('/artist/$artistId', {});
    if (data.isEmpty || data.containsKey('error')) return null;
    return DiscoveredArtist.fromJson(data);
  }

  Future<List<DiscoveredAlbum>> getArtistAlbums(int artistId,
      {int limit = 50}) async {
    final data = await _get('/artist/$artistId/albums', {'limit': '$limit'});
    final list = data['data'] as List? ?? [];
    final results = list.map((j) => DiscoveredAlbum.fromJson(j)).toList();
    await _markLibraryStatus(results);
    return results;
  }

  // ── DÉTAILS ALBUM ──

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

  /// Marque les albums comme présents dans la bibliothèque locale (NAS).
  Future<void> _markLibraryStatus(List<DiscoveredAlbum> albums) async {
    final localTracks = _music.allTracks;
    final localAlbums = _music.albums;

    for (final album in albums) {
      // Match par nom d'artiste + nom d'album (normalisé)
      final normalizedArtist = _normalize(album.artistName);
      final normalizedTitle = _normalize(album.title);

      album.isInLibrary = localAlbums.any((a) {
        return _normalize(a.artist) == normalizedArtist &&
            _normalize(a.title) == normalizedTitle;
      });

      // Fallback : au moins une track de cet album est présente
      if (!album.isInLibrary) {
        album.isInLibrary = localTracks.any((t) {
          return _normalize(t.artist) == normalizedArtist &&
              _normalize(t.album) == normalizedTitle;
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
        return _normalize(t.artist) == normalizedArtist &&
            _normalize(t.title) == normalizedTitle &&
            _normalize(t.album) == normalizedAlbum;
      });
    }
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ── HTTP ──

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
