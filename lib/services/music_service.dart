import 'dart:async';
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
import 'navidrome_service.dart';
import 'package:http/http.dart' as http;

class MusicService {
  static final MusicService _instance = MusicService._internal();
  factory MusicService() => _instance;
  MusicService._internal();

  List<Track> _allTracks = [];
  List<Album> _albums = [];
  List<Playlist> _playlists = [];
  bool _initialized = false;
  String? _coversDir;
  List<Map<String, dynamic>> _missingTracks = [];
  List<Map<String, dynamic>> get missingTracks =>
      List.unmodifiable(_missingTracks);

  // Cache en memoire des covers existantes pour eviter les existsSync()
  final Set<String> _existingCovers = {};
  Timer? _saveDebounceTimer;

  List<Track> get allTracks => _navidromeTracks;
  List<Album> get albums => List.unmodifiable(_albums);
  List<Playlist> get playlists => List.unmodifiable(_playlists);

  final NavidromeService _navidrome = NavidromeService();
  List<Track> _navidromeTracks = [];
  Map<String, String> _offlineFiles = {}; // navidrome_id -> local path

  List<Track> get navidromeTracks => List.unmodifiable(_navidromeTracks);
  bool isTrackDownloaded(String trackId) => _offlineFiles.containsKey(trackId);
  String? getOfflinePath(String trackId) => _offlineFiles[trackId];

  String? _currentUserId;

  void setCurrentUser(String? userId) {
    _currentUserId = userId;
    _initialized = false;
  }

  String get _cacheFileName {
    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      return 'library_$_currentUserId.json';
    }
    return 'library.json';
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _coversDir = await _getCoversDir();
    await _loadFromCache();
    await _refreshCoverCache();
    _initialized = true;
  }

  Future<String> _getCoversDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'covers'));
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Rafraichit le cache des covers existantes (appele une fois au demarrage)
  Future<void> _refreshCoverCache() async {
    _existingCovers.clear();
    if (_coversDir == null) return;
    final dir = Directory(_coversDir!);
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File) _existingCovers.add(entity.path);
    }
  }

  /// Verifie si une cover existe (utilise le cache, pas de I/O synchrone)
  bool coverExists(String? path) {
    if (path == null) return false;
    if (path.startsWith('http')) return true;
    return _existingCovers.contains(path);
  }

  Future<String?> _saveCover(Uint8List bytes, String trackId) async {
    if (_coversDir == null) return null;
    try {
      final ext = _detectImageFormat(bytes);
      final filePath = p.join(_coversDir!, '${trackId.hashCode}.$ext');
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      _existingCovers.add(filePath);
      return filePath;
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
      if (!['.mp3', '.flac', '.m4a', '.ogg', '.wav'].contains(ext)) continue;

      try {
        final byteData = await rootBundle.load(assetPath);
        final fileName = p.basenameWithoutExtension(assetPath);
        String title = fileName;
        final numberMatch = RegExp(r'^\d+\.\s*').firstMatch(fileName);
        if (numberMatch != null) {
          title = fileName.substring(numberMatch.end).trim();
        }

        final album = p.basename(p.dirname(assetPath));
        final artist = _extractArtistFromAlbum(album);

        String? coverPath;
        try {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File(p.join(tempDir.path, p.basename(assetPath)));
          await tempFile.writeAsBytes(byteData.buffer.asUint8List());

          final metadata = await MetadataGod.readMetadata(file: tempFile.path);
          if (metadata.picture != null) {
            coverPath = await _saveCover(metadata.picture!.data, assetPath);
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

    if (loaded.isNotEmpty) {
      final localTracks = _allTracks
          .where(
              (t) => t.filePath != null && !t.filePath!.startsWith('assets/'))
          .toList();

      _allTracks = [...localTracks, ...loaded];
      rebuildAlbums();
      _debouncedSave();
    }
  }

  Future<void> scanDirectory(String dirPath) async {
    final normalizedPath = dirPath.replaceAll(r'\\', r'\');
    final dir = Directory(normalizedPath);

    if (!await dir.exists()) {
      print('DOSSIER NON TROUVE: $normalizedPath');
      return;
    }

    final List<Track> scanned = [];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (['.mp3', '.flac', '.m4a', '.ogg', '.wav'].contains(ext)) {
          final track = await parseFile(entity.path);
          scanned.add(track);
        }
      }
    }

    if (scanned.isNotEmpty) {
      final assetTracks = _allTracks
          .where((t) => t.filePath != null && t.filePath!.startsWith('assets/'))
          .toList();

      _allTracks = [...assetTracks, ...scanned];
      rebuildAlbums();
      _debouncedSave();
    }
  }

  void rebuildAlbums() {
    // Préserver les albums existants par ID (isSaved, artist)
    final existingAlbums = <String, Album>{};
    for (final a in _albums) {
      existingAlbums[a.id] = a;
    }

    final Map<String, List<Track>> albumMap = {};
    for (final track in _navidromeTracks) {
      albumMap.putIfAbsent(track.album, () => []).add(track);
    }

    final newAlbums = <Album>[];
    for (final entry in albumMap.entries) {
      final tracks = entry.value;
      String? albumCover;
      for (final track in tracks) {
        if (track.coverPath != null) {
          albumCover = track.coverPath;
          break;
        }
      }

      final firstTrack = tracks.first;
      final navidromeId = firstTrack.albumId;
      final id = navidromeId != null
          ? 'navidrome_$navidromeId'
          : entry.key.hashCode.toString();

      // Préserver l'artiste et isSaved de l'album existant
      final existing = existingAlbums[id];
      final artist =
          firstTrack.albumArtist ?? existing?.artist ?? firstTrack.artist;

      newAlbums.add(Album(
        id: id,
        title: entry.key,
        artist: artist,
        trackIds: tracks.map((t) => t.id).toList(),
        isSaved: existing?.isSaved ?? false,
        coverPath: albumCover,
      ));
    }

    _albums = newAlbums;
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

  List<Track> get likedTracks {
    final liked = _allTracks.where((t) => t.isLiked).toList();
    liked.sort((a, b) {
      final da = a.dateAdded ?? DateTime(2000);
      final db = b.dateAdded ?? DateTime(2000);
      if (da == db) {
        return _allTracks.indexOf(a).compareTo(_allTracks.indexOf(b));
      }
      return db.compareTo(da);
    });
    for (final t in liked.take(5)) {
      print('LIKE ORDER: ${t.title} | date=${t.dateAdded}');
    }
    return liked;
  }

  List<Album> get likedAlbums => _albums.where((a) => a.isSaved).toList();

  Future<void> toggleLikeAlbum(String albumId) async {
    final album = _albums.firstWhere(
      (a) => a.id == albumId,
      orElse: () => throw Exception('Album $albumId not found'),
    );
    album.isSaved = !album.isSaved;

    if (album.id.startsWith('navidrome_')) {
      final cleanId = album.id.replaceFirst('navidrome_', '');
      if (album.isSaved) {
        await _navidrome.starAlbum(cleanId);
      } else {
        await _navidrome.unstarAlbum(cleanId);
      }
    }
    _debouncedSave();
  }

  Future toggleLike(String trackId) async {
    final track = _allTracks.firstWhere(
      (t) => t.id == trackId,
      orElse: () => throw Exception('Track $trackId not found'),
    );
    track.isLiked = !track.isLiked;
    if (track.isLiked && track.dateAdded == null) {
      track.dateAdded = DateTime.now();
    }
    if (track.id.startsWith('navidrome_')) {
      if (track.isLiked) {
        await _navidrome.starTrack(track.id);
      } else {
        await _navidrome.unstarTrack(track.id);
      }
    }
    _debouncedSave();
  }

  Future<void> createPlaylist(String name) async {
    _playlists.add(Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
    ));
    _debouncedSave();
  }

  Future<void> addToPlaylist(String playlistId, String trackId) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    if (!playlist.trackIds.contains(trackId)) {
      playlist.trackIds.add(trackId);
      _debouncedSave();
    }
  }

  Future<void> removeFromPlaylist(String playlistId, String trackId) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    playlist.trackIds.remove(trackId);
    _debouncedSave();
  }

  Future<void> recordPlay(String trackId) async {
    final track = _allTracks.firstWhere((t) => t.id == trackId);
    track.playCount++;
    track.lastPlayed = DateTime.now();
    _debouncedSave();
  }

  Future _getCacheFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(appDir.path, 'cache'));
    await cacheDir.create(recursive: true);
    return File(p.join(cacheDir.path, _cacheFileName));
  }

  Future _saveToCache() async {
    final file = await _getCacheFile();
    final data = {
      'navidromeTracks': _navidromeTracks.map((t) => t.toJson()).toList(),
      'offlineFiles': _offlineFiles,
      'missingTracks': _missingTracks,
      'playlists': _playlists
          .map((pl) => {
                'id': pl.id,
                'name': pl.name,
                'trackIds': pl.trackIds,
                'createdAt': pl.createdAt.toIso8601String(),
                'isSaved': pl.isSaved,
              })
          .toList(),
      'albums': _albums.map((a) => a.toJson()).toList(),
    };
    await file.writeAsString(jsonEncode(data));
  }

  void addTrack(Track track) {
    if (!_allTracks.any((t) => t.id == track.id)) {
      _allTracks.add(track);
    }
  }

  Future<void> saveToCache() async {
    _saveDebounceTimer?.cancel();
    await _saveToCache();
  }

  Future _loadFromCache() async {
    final file = await _getCacheFile();
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString());

        _navidromeTracks = (data['navidromeTracks'] as List?)
                ?.map((json) => Track.fromJson(json))
                .toList() ??
            [];
        _allTracks = List.from(_navidromeTracks);

        _offlineFiles = Map<String, String>.from(data['offlineFiles'] ?? {});

        _playlists = (data['playlists'] as List?)
                ?.map((pl) => Playlist(
                      id: pl['id'],
                      name: pl['name'],
                      trackIds: List<String>.from(pl['trackIds'] ?? []),
                      createdAt: DateTime.parse(pl['createdAt']),
                      isSaved: pl['isSaved'] ?? true,
                    ))
                .toList() ??
            [];
        _missingTracks = (data['missingTracks'] as List?)
                ?.map((m) => Map<String, dynamic>.from(m))
                .toList() ??
            [];
        _albums = (data['albums'] as List?)
                ?.map((json) => Album.fromJson(json))
                .toList() ??
            [];

        // Ne rebuild que si pas d'albums en cache (premier chargement)
        if (_albums.isEmpty) {
          rebuildAlbums();
        }
      } catch (e) {
        print('ERREUR CHARGEMENT CACHE: $e');
      }
    }
  }

  Future<void> rescanCoversForExistingTracks() async {
    final localTracks = _allTracks
        .where((t) => t.filePath != null && !t.filePath!.startsWith('assets/'))
        .toList();

    int updated = 0;
    for (final track in localTracks) {
      if (track.coverPath != null) {
        final file = File(track.coverPath!);
        if (await file.exists()) continue;
      }

      try {
        final metadata = await MetadataGod.readMetadata(file: track.filePath!);
        if (metadata.picture != null) {
          final coverPath =
              await _saveCover(metadata.picture!.data, track.filePath!);
          if (coverPath != null) {
            final index = _allTracks.indexWhere((t) => t.id == track.id);
            if (index != -1) {
              _allTracks[index] = Track(
                id: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration,
                filePath: track.filePath,
                coverPath: coverPath,
                isLiked: track.isLiked,
                playCount: track.playCount,
                lastPlayed: track.lastPlayed,
              );
              updated++;
            }
          }
        }
      } catch (e) {
        print('ERREUR COVER ${track.filePath}: $e');
      }
    }

    if (updated > 0) {
      rebuildAlbums();
      _debouncedSave();
    }
    print('RESCAN COVERS: $updated covers ajoutees');
  }

  void _debouncedSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(seconds: 2), () async {
      await _saveToCache();
    });
  }

  Future<void> syncWithNavidrome() async {
    print('SYNC NAVIDROME...');
    final fresh = await _navidrome.fetchAllTracks();
    final starredIds = await _navidrome.fetchStarredTrackIds();
    final starredAlbumIds = await _navidrome.fetchStarredAlbumIds();

    final localData = <String, Map<String, dynamic>>{};
    for (final t in _navidromeTracks) {
      localData[t.id] = {
        'isLiked': t.isLiked,
        'dateAdded': t.dateAdded,
        'playCount': t.playCount,
        'lastPlayed': t.lastPlayed,
      };
    }

    for (final t in fresh) {
      if (starredIds.contains(t.id)) t.isLiked = true;
      final local = localData[t.id];
      if (local != null) {
        t.isLiked = local['isLiked'] ?? t.isLiked;
        t.dateAdded = local['dateAdded'];
        t.playCount = local['playCount'] ?? t.playCount;
        t.lastPlayed = local['lastPlayed'] ?? t.lastPlayed;
      }
    }

    _navidromeTracks = fresh;
    _allTracks = List.from(_navidromeTracks);
    rebuildAlbums();

    // Reset isSaved sur tous les albums puis reapplique les starred
    for (final album in _albums) {
      album.isSaved = false;
    }
    for (final album in _albums) {
      if (starredAlbumIds.contains(album.id)) {
        album.isSaved = true;
      }
    }

    _debouncedSave();
    print('SYNC NAVIDROME: ${_navidromeTracks.length} tracks');
  }

  Future<void> downloadTrack(Track track) async {
    if (!track.filePath!.startsWith('http')) return;

    final navidromeId = track.id.replaceFirst('navidrome_', '');
    final url = _navidrome.getStreamUrl(navidromeId);

    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(minutes: 2));
      if (response.statusCode == 200) {
        final appDir = await getApplicationDocumentsDirectory();
        final offlineDir = Directory('${appDir.path}/offline_music');
        await offlineDir.create(recursive: true);

        final ext = '.mp3'; // Navidrome stream souvent en MP3
        final filePath = '${offlineDir.path}/${track.id.hashCode}$ext';
        await File(filePath).writeAsBytes(response.bodyBytes);

        _offlineFiles[track.id] = filePath;
        _debouncedSave();
        print('DOWNLOADED: ${track.title} -> $filePath');
      }
    } catch (e) {
      print('DOWNLOAD ERROR ${track.title}: $e');
    }
  }

  void setMissingTracks(List<Map<String, dynamic>> tracks) {
    _missingTracks = tracks;
    _debouncedSave();
  }

  void clearMissingTracks() {
    _missingTracks = [];
    _debouncedSave();
  }
}
