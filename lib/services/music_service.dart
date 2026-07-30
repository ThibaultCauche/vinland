import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/track.dart';
import '../models/album.dart';
import '../models/playlist.dart';

class MusicService {
  static final MusicService _instance = MusicService._internal();
  factory MusicService() => _instance;
  MusicService._internal();

  List<Track> _allTracks = [];
  List<Album> _albums = [];
  List<Playlist> _playlists = [];
  List<String> _searchHistory = [];
  bool _initialized = false;

  List<Track> get allTracks => List.unmodifiable(_allTracks);
  List<Album> get albums => List.unmodifiable(_albums);
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<String> get searchHistory => List.unmodifiable(_searchHistory);

  Future<void> initialize() async {
    if (_initialized) return;
    await _loadFromCache();
    _initialized = true;
  }

  Future<void> scanAssetsMusic() async {
    print('SCAN DES ASSETS...');

    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = jsonDecode(manifestContent);

    final List<Track> loaded = [];

    for (final String assetPath in manifest.keys) {
      if (!assetPath.startsWith('assets/music/')) continue;

      final ext = p.extension(assetPath).toLowerCase();
      if (ext != '.mp3' &&
          ext != '.flac' &&
          ext != '.m4a' &&
          ext != '.ogg' &&
          ext != '.wav') continue;

      try {
        final byteData = await rootBundle.load(assetPath);
        print('FICHIER CHARGÉ: $assetPath (${byteData.lengthInBytes} bytes)');

        final fileName = p.basenameWithoutExtension(assetPath);

        String title = fileName;
        final numberMatch = RegExp(r'^\d+\.\s*').firstMatch(fileName);
        if (numberMatch != null) {
          title = fileName.substring(numberMatch.end).trim();
        }

        final album = p.basename(p.dirname(assetPath));
        final artist = _extractArtistFromAlbum(album);

        loaded.add(Track(
          id: assetPath,
          title: title,
          artist: artist,
          album: album,
          duration: const Duration(minutes: 3),
          filePath: assetPath,
        ));
      } catch (e) {
        print('ERREUR FICHIER: $assetPath - $e');
      }
    }

    print('${loaded.length} MUSIQUES ASSETS CHARGÉES');

    if (loaded.isNotEmpty) {
      final localTracks = _allTracks
          .where(
              (t) => t.filePath != null && !t.filePath!.startsWith('assets/'))
          .toList();

      _allTracks = [...localTracks, ...loaded];
      rebuildAlbums();
      await _saveToCache();
    }
  }

  Future<void> scanDirectory(String dirPath) async {
    final normalizedPath = dirPath.replaceAll(r'\\', r'\');
    final dir = Directory(normalizedPath);

    if (!await dir.exists()) {
      print('DOSSIER NON TROUVE: $normalizedPath');
      return;
    }

    print('SCAN DE: $normalizedPath');
    final List<Track> scanned = [];

    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (ext == '.mp3' ||
              ext == '.flac' ||
              ext == '.m4a' ||
              ext == '.ogg' ||
              ext == '.wav') {
            print('FICHIER TROUVE: ${entity.path}');
            final track = parseFile(entity.path);
            scanned.add(track);
          }
        }
      }
    } catch (e) {
      print('ERREUR SCAN: $e');
    }

    print('${scanned.length} MUSIQUES TROUVEES');

    if (scanned.isNotEmpty) {
      final assetTracks = _allTracks
          .where((t) => t.filePath != null && t.filePath!.startsWith('assets/'))
          .toList();

      _allTracks = [...assetTracks, ...scanned];
      rebuildAlbums();
      await _saveToCache();
    }
  }

  void rebuildAlbums() {
    final Map<String, List<Track>> albumMap = {};
    for (final track in _allTracks) {
      albumMap.putIfAbsent(track.album, () => []).add(track);
    }

    _albums = albumMap.entries
        .map((e) => Album(
              id: e.key.hashCode.toString(),
              title: e.key,
              artist: e.value.first.artist,
              trackIds: e.value.map((t) => t.id).toList(),
              isSaved: true,
            ))
        .toList();

    print('${_albums.length} ALBUMS RECONSTRUITS');
    for (final album in _albums) {
      print('  - ${album.title} (${album.trackCount} titres)');
    }
  }

  Track parseFile(String filePath) {
    final fileName = p.basenameWithoutExtension(filePath);
    final albumDir = p.basename(p.dirname(filePath)); // Album
    final artistDir = p.basename(
        p.dirname(p.dirname(filePath))); // Artiste (parent de l'album)

    String title = fileName;
    final numberMatch = RegExp(r'^\d+\.\s*').firstMatch(fileName);
    if (numberMatch != null) {
      title = fileName.substring(numberMatch.end).trim();
    }

    // L'artiste = le dossier parent de l'album, ou fallback sur l'album
    String artist = artistDir;
    if (artistDir == '.' || artistDir == '/' || artistDir == filePath) {
      artist = _extractArtistFromAlbum(albumDir);
    }

    return Track(
      id: filePath,
      title: title,
      artist: artist,
      album: albumDir,
      duration: const Duration(minutes: 3),
      filePath: filePath,
    );
  }

  String _extractArtistFromAlbum(String albumName) {
    if (albumName.contains(':')) {
      final parts = albumName.split(':');
      final first = parts[0].trim();

      if (RegExp(r'^Vol\.?\s*\d+', caseSensitive: false).hasMatch(first)) {
        return parts.sublist(1).join(':').trim();
      }
      return first;
    }

    final parenIdx = albumName.indexOf('(');
    if (parenIdx > 0) {
      return albumName.substring(0, parenIdx).trim();
    }

    return albumName;
  }

  List<Track> searchTracks(String query) {
    if (query.isEmpty) return [];
    final lower = query.toLowerCase();
    return _allTracks
        .where((t) =>
            t.title.toLowerCase().contains(lower) ||
            t.artist.toLowerCase().contains(lower) ||
            t.album.toLowerCase().contains(lower))
        .toList();
  }

  List<Album> searchAlbums(String query) {
    if (query.isEmpty) return [];
    final lower = query.toLowerCase();
    return _albums
        .where((a) =>
            a.title.toLowerCase().contains(lower) ||
            a.artist.toLowerCase().contains(lower))
        .toList();
  }

  void addSearchQuery(String query) {
    if (query.isEmpty) return;
    _searchHistory.remove(query);
    _searchHistory.insert(0, query);
    if (_searchHistory.length > 20) _searchHistory.removeLast();
    _saveToCache();
  }

  List<Track> get likedTracks => _allTracks.where((t) => t.isLiked).toList();

  void toggleLike(String trackId) {
    final track = _allTracks.firstWhere((t) => t.id == trackId);
    track.isLiked = !track.isLiked;
    _saveToCache();
  }

  void createPlaylist(String name) {
    _playlists.add(Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
    ));
    _saveToCache();
  }

  void addToPlaylist(String playlistId, String trackId) {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    if (!playlist.trackIds.contains(trackId)) {
      playlist.trackIds.add(trackId);
      _saveToCache();
    }
  }

  void removeFromPlaylist(String playlistId, String trackId) {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    playlist.trackIds.remove(trackId);
    _saveToCache();
  }

  void recordPlay(String trackId) {
    final track = _allTracks.firstWhere((t) => t.id == trackId);
    track.playCount++;
    track.lastPlayed = DateTime.now();
    _saveToCache();
  }

  void removeSearchQuery(String query) {
    _searchHistory.remove(query);
    _saveToCache();
  }

  void clearSearchHistory() {
    _searchHistory.clear();
    _saveToCache();
  }

  Future<void> _saveToCache() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(appDir.path, 'cache'));
    await cacheDir.create(recursive: true);

    final file = File(p.join(cacheDir.path, 'library.json'));
    final data = {
      'tracks': _allTracks.map((t) => t.toJson()).toList(),
      'playlists': _playlists
          .map((pl) => {
                'id': pl.id,
                'name': pl.name,
                'trackIds': pl.trackIds,
                'createdAt': pl.createdAt.toIso8601String(),
                'isSaved': pl.isSaved,
              })
          .toList(),
      'searchHistory': _searchHistory,
    };
    await file.writeAsString(jsonEncode(data));
  }

  void addTrack(Track track) {
    if (!_allTracks.any((t) => t.id == track.id)) {
      _allTracks.add(track);
    }
  }

  Future<void> saveToCache() async => _saveToCache();

  Future<void> _loadFromCache() async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(appDir.path, 'cache', 'library.json'));
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString());
        _allTracks = (data['tracks'] as List)
            .map((json) => Track.fromJson(json))
            .toList();
        _searchHistory = List<String>.from(data['searchHistory'] ?? []);

        rebuildAlbums();
        print(
            'CACHE CHARGÉ: ${_allTracks.length} titres, ${_albums.length} albums');
      } catch (e) {
        print('ERREUR CHARGEMENT CACHE: $e');
        await scanAssetsMusic();
      }
    } else {
      await scanAssetsMusic();
    }
  }
}
