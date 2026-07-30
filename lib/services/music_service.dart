import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:metadata_god/metadata_god.dart';
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
  String? _coversDir;

  List<Track> get allTracks => List.unmodifiable(_allTracks);
  List<Album> get albums => List.unmodifiable(_albums);
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<String> get searchHistory => List.unmodifiable(_searchHistory);

  Future<void> initialize() async {
    if (_initialized) return;
    _coversDir = await _getCoversDir();
    await _loadFromCache();
    _initialized = true;
  }

  Future<String> _getCoversDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'covers'));
    await dir.create(recursive: true);
    return dir.path;
  }

  Future<String?> _saveCover(Uint8List bytes, String trackId) async {
    if (_coversDir == null) return null;
    try {
      final ext = _detectImageFormat(bytes);
      final file = File(p.join(_coversDir!, '${trackId.hashCode}.$ext'));
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      print('ERREUR SAUVEGARDE COVER: $e');
      return null;
    }
  }

  String _detectImageFormat(Uint8List bytes) {
    if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg';
    if (bytes.length > 8 && bytes[0] == 0x89) return 'png';
    return 'jpg';
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

        // Extraction cover depuis asset
        String? coverPath;
        try {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File(p.join(tempDir.path, p.basename(assetPath)));
          await tempFile.writeAsBytes(byteData.buffer.asUint8List());

          final metadata = await MetadataGod.readMetadata(file: tempFile.path);
          if (metadata.picture != null) {
            coverPath = await _saveCover(metadata.picture!.data, assetPath);
            print('COVER EXTRAITE ASSET: $assetPath -> $coverPath');
          }
          await tempFile.delete();
        } catch (e) {
          print('ERREUR COVER ASSET: $assetPath - $e');
        }

        loaded.add(Track(
          id: assetPath,
          title: title,
          artist: artist,
          album: album,
          duration: const Duration(minutes: 3),
          filePath: assetPath,
          coverPath: coverPath,
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
            final track = await parseFile(entity.path);
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

    _albums = albumMap.entries.map((e) {
      final tracks = e.value;
      String? albumCover;
      for (final track in tracks) {
        if (track.coverPath != null) {
          albumCover = track.coverPath;
          break;
        }
      }

      return Album(
        id: e.key.hashCode.toString(),
        title: e.key,
        artist: e.value.first.artist,
        trackIds: e.value.map((t) => t.id).toList(),
        isSaved: true,
        coverPath: albumCover,
      );
    }).toList();

    print('${_albums.length} ALBUMS RECONSTRUITS');
    for (final album in _albums) {
      print(
          '  - ${album.title} (${album.trackCount} titres, cover: ${album.coverPath != null ? 'OUI' : 'NON'})');
    }
  }

  Future<Track> parseFile(String filePath) async {
    final fileName = p.basenameWithoutExtension(filePath);
    final albumDir = p.basename(p.dirname(filePath));
    final artistDir = p.basename(p.dirname(p.dirname(filePath)));

    String title = fileName;
    String artist = artistDir;
    String album = albumDir;
    String? coverPath;
    Duration duration = const Duration(minutes: 3);

    try {
      final metadata = await MetadataGod.readMetadata(file: filePath);

      title = metadata.title ?? _extractTitleFromFileName(fileName);
      artist = metadata.artist ?? artistDir;
      album = metadata.album ?? albumDir;

      if (metadata.picture != null) {
        coverPath = await _saveCover(metadata.picture!.data, filePath);
        print('COVER EXTRAITE: $filePath -> $coverPath');
      }

      if (metadata.durationMs != null && metadata.durationMs! > 0) {
        duration = Duration(milliseconds: metadata.durationMs!.toInt());
      }
    } catch (e) {
      print('ERREUR METADATA: $filePath - $e');
      title = _extractTitleFromFileName(fileName);
    }

    return Track(
      id: filePath,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      filePath: filePath,
      coverPath: coverPath,
    );
  }

  String _extractTitleFromFileName(String fileName) {
    String title = fileName;
    final numberMatch = RegExp(r'^\d+\.\s*').firstMatch(fileName);
    if (numberMatch != null) {
      title = fileName.substring(numberMatch.end).trim();
    }
    return title;
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
      }
    }
  }
}
