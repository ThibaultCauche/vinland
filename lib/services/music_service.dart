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

    // Charge les musiques depuis les assets si aucune n'est en cache
    if (_allTracks.isEmpty) {
      await _loadAssetsMusic();
    }

    _initialized = true;
  }

  Future<void> _loadAssetsMusic() async {
    final assetFiles = [
      'assets/music/1. The Bridge.ogg',
      'assets/music/2. The City of Progress.ogg',
      'assets/music/3. Intruders.ogg',
    ];

    final List<Track> loaded = [];

    for (final assetPath in assetFiles) {
      try {
        // Vérifie que le fichier existe
        final byteData = await rootBundle.load(assetPath);
        print('FICHIER CHARGÉ: $assetPath (${byteData.lengthInBytes} bytes)');

        final fileName = assetPath.split('/').last.replaceAll('.ogg', '');
        String title = fileName;
        final numberMatch = RegExp(r'^\d+\.\s*').firstMatch(fileName);
        if (numberMatch != null) {
          title = fileName.substring(numberMatch.end).trim();
        }

        loaded.add(Track(
          id: assetPath,
          title: title,
          artist: 'Arcane',
          album: 'Arcane League of Legends',
          duration: const Duration(minutes: 3),
          filePath: assetPath,
        ));
      } catch (e) {
        print('ERREUR FICHIER: $assetPath - $e');
      }
    }

    _allTracks = loaded;
    print('${_allTracks.length} MUSIQUES CHARGÉES');

    // Sauvegarde en cache
    await _saveToCache();
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
    final Map<String, List<Track>> albumMap = {};

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
            final track = _parseFile(entity.path);
            scanned.add(track);
            albumMap.putIfAbsent(track.album, () => []).add(track);
          }
        }
      }
    } catch (e) {
      print('ERREUR SCAN: $e');
    }

    print('${scanned.length} MUSIQUES TROUVEES');

    if (scanned.isNotEmpty) {
      _allTracks = scanned;
      _albums = albumMap.entries
          .map((e) => Album(
                id: e.key.hashCode.toString(),
                title: e.key,
                artist: e.value.first.artist,
                trackIds: e.value.map((t) => t.id).toList(),
                isSaved: true,
              ))
          .toList();
      await _saveToCache();
    }
  }

  Track _parseFile(String filePath) {
    final fileName = p.basenameWithoutExtension(filePath);

    String title = fileName;
    final numberMatch = RegExp(r'^\d+\.\s*').firstMatch(fileName);
    if (numberMatch != null) {
      title = fileName.substring(numberMatch.end).trim();
    }

    final parentDir = p.basename(p.dirname(filePath));
    String artist = parentDir;

    final grandParent = p.basename(p.dirname(p.dirname(filePath)));
    if (grandParent.isNotEmpty &&
        grandParent != '.' &&
        grandParent != 'Music') {
      artist = grandParent;
    }

    String album = parentDir;

    return Track(
      id: filePath.hashCode.toString(),
      title: title,
      artist: artist,
      album: album,
      duration: const Duration(minutes: 3),
      filePath: filePath,
    );
  }

  // Recherche
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

  // Tracks likes
  List<Track> get likedTracks => _allTracks.where((t) => t.isLiked).toList();

  void toggleLike(String trackId) {
    final track = _allTracks.firstWhere((t) => t.id == trackId);
    track.isLiked = !track.isLiked;
    _saveToCache();
  }

  // Playlists
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

  // Historique de lecture
  void recordPlay(String trackId) {
    final track = _allTracks.firstWhere((t) => t.id == trackId);
    track.playCount++;
    track.lastPlayed = DateTime.now();
    _saveToCache();
  }

  // Cache
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

        final albumMap = <String, List<Track>>{};
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
      } catch (e) {
        print('ERREUR CHARGEMENT CACHE: $e');
      }
    }
  }
}
