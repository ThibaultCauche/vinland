import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/discovered_artist.dart';
import '../models/discovered_album.dart';
import '../models/discovered_track.dart';
import '../models/track.dart';
import 'matching_service.dart';
import 'music_service.dart';

class DiscoveryService {
  static final DiscoveryService _instance = DiscoveryService._internal();
  factory DiscoveryService() => _instance;
  DiscoveryService._internal();

  final String _baseUrl = 'https://api.deezer.com';
  final MusicService _music = MusicService();

  // ── CACHE DISQUE ──
  // Les metadonnees Deezer (recherche album/artiste, tracklists) changent
  // rarement -- sans ce cache, chaque ouverture d'un ecran album/artiste
  // refaisait les memes appels reseau a chaque fois, ce qui rendait ces
  // pages lentes a s'afficher meme en revisitant un contenu deja vu.
  static const Duration _cacheTtl = Duration(days: 7);
  final Map<String, Map<String, dynamic>> _memoryCache = {};
  Directory? _cacheDir;

  Future<Directory> _getCacheDir() async {
    final existing = _cacheDir;
    if (existing != null) return existing;
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'deezer_cache'));
    await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  String _cacheKey(String endpoint, Map<String, String> params) {
    final sortedEntries = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final raw =
        '$endpoint?${sortedEntries.map((e) => '${e.key}=${e.value}').join('&')}';
    return md5.convert(utf8.encode(raw)).toString();
  }

  Future<Map<String, dynamic>?> _readDiskCache(String key) async {
    try {
      final dir = await _getCacheDir();
      final file = File(p.join(dir.path, '$key.json'));
      if (!await file.exists()) return null;
      final stat = await file.stat();
      if (DateTime.now().difference(stat.modified) > _cacheTtl) return null;
      final content = jsonDecode(await file.readAsString());
      return content is Map<String, dynamic> ? content : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDiskCache(String key, Map<String, dynamic> data) async {
    try {
      final dir = await _getCacheDir();
      final file = File(p.join(dir.path, '$key.json'));
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

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

    // Index : artiste "coeur" → liste de tracks locales (evite un scan
    // complet de la bibliotheque pour le fallback de chaque album Deezer).
    final tracksByArtist = <String, List<Track>>{};
    for (final t in localTracks) {
      final artist = MatchingService.coreArtist(t.artist);
      tracksByArtist.putIfAbsent(artist, () => []).add(t);
    }

    for (final album in albums) {
      final coreArtist = MatchingService.coreArtist(album.artistName);

      // 1. Match par nom d'album local
      album.isInLibrary = localAlbums.any((a) {
        return MatchingService.artistsMatch(a.artist, album.artistName) &&
            MatchingService.albumsMatch(a.title, album.title);
      });

      // 2. Fallback : match par tracks locales (même nom d'album approximatif)
      if (!album.isInLibrary) {
        final artistTracks = tracksByArtist[coreArtist] ?? [];
        final localAlbumNames = <String>{};
        for (final t in artistTracks) {
          localAlbumNames.add(t.album);
        }
        album.isInLibrary = localAlbumNames.any((name) {
          return MatchingService.albumsMatch(name, album.title);
        });
      }
    }
  }

  Future<void> _markTrackLibraryStatus(List<DiscoveredTrack> tracks) async {
    final localTracks = _music.allTracks;

    for (final track in tracks) {
      // Deezer laisse parfois l'album vide pour un titre (compilation, live,
      // single mal catalogue) -- DiscoveredTrack retombe alors sur "Inconnu",
      // qui ne correspondra jamais au vrai nom d'album tague localement. Dans
      // ce cas on ne compare que artiste+titre plutot que de bloquer
      // indefiniment le match sur un champ qui n'a jamais ete une vraie
      // valeur d'album.
      final albumIsPlaceholder = track.albumName == 'Inconnu';
      track.isInLibrary = localTracks.any((t) {
        return MatchingService.artistsMatch(t.artist, track.artistName) &&
            (albumIsPlaceholder ||
                MatchingService.albumsMatch(t.album, track.albumName)) &&
            MatchingService.titlesMatch(t.title, track.title);
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
      return MatchingService.artistsMatch(t.artist, album.artistName);
    }).toList();

    int matches = 0;
    for (final dt in deezerTracks) {
      if (localTracks.any((lt) => MatchingService.titlesMatch(lt.title, dt.title))) {
        matches++;
      }
    }

    return matches / deezerTracks.length >= minMatchRatio;
  }

  Future<Map<String, dynamic>> _get(
      String endpoint, Map<String, String> params) async {
    final key = _cacheKey(endpoint, params);

    final memoryHit = _memoryCache[key];
    if (memoryHit != null) return memoryHit;

    final diskHit = await _readDiskCache(key);
    if (diskHit != null) {
      _memoryCache[key] = diskHit;
      return diskHit;
    }

    final uri =
        Uri.parse('$_baseUrl$endpoint').replace(queryParameters: params);
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _memoryCache[key] = data;
        unawaited(_writeDiskCache(key, data));
        return data;
      }
    } catch (e) {
      debugPrint('DiscoveryService error: $e');
    }
    return {};
  }
}
