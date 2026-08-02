import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import '../models/track.dart';
import '../services/music_service.dart';
import '../services/auth_service.dart';
import '../services/audio_handler.dart';
import '../models/album.dart';
import '../screens/artist_screen.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:palette_generator/palette_generator.dart';

class AppState extends ChangeNotifier {
  final MusicService _music = MusicService();
  final AuthService _auth = AuthService();
  final VinlandAudioHandler _audioHandler;

  // Player state
  Track? currentTrack;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  List<Track> queue = [];
  int currentIndex = -1;
  int _lastColorRequest = 0;
  final Map<String, Color> _colorCache = {};
  int _lastPositionNotify = 0;

  // UI state
  int currentTab = 0;
  String searchQuery = '';
  bool showSearchResults = false;
  bool get isCurrentTrackLiked =>
      currentTrack != null &&
      _music.likedTracks.any((t) => t.id == currentTrack!.id);

  // Missing tracks from streaming import
  List<Map<String, String>> _missingTracks = [];
  List<Map<String, String>> get missingTracks =>
      List.unmodifiable(_missingTracks);

  // Getters
  List<Track> get allTracks => _music.allTracks;
  List<Track> get likedTracks => _music.likedTracks;
  List<Track> get searchResults {
    if (searchQuery.isEmpty) return [];
    return _music.searchTracks(searchQuery);
  }

  List<String> get searchHistory => _music.searchHistory;
  bool get isLoggedIn => _auth.isLoggedIn;
  String? get userName => _auth.userName;
  String? get userEmail => _auth.userEmail;
  List<Album> get albums => _music.albums;
  MusicService get musicService => _music;
  bool get isLocalMode => true;
  Color? dominantColor;

  // Overlay navigation
  final List<Widget> _overlayStack = [];
  List<Widget> get overlayStack => List.unmodifiable(_overlayStack);
  Widget? get currentOverlay =>
      _overlayStack.isNotEmpty ? _overlayStack.last : null;

  AppState({required VinlandAudioHandler audioHandler})
      : _audioHandler = audioHandler {
    _audioHandler.customActionStream.listen((action) {
      if (action == 'add_to_likes' && currentTrack != null) {
        toggleLike(currentTrack!.id);
      }
    });

    // FIX: throttle position — max 1 notify toutes les 500ms
    _audioHandler.player.positionStream.listen((pos) {
      position = pos;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastPositionNotify > 500) {
        _lastPositionNotify = now;
        notifyListeners();
      }
    });
    _audioHandler.player.durationStream.listen((dur) {
      if (dur != null && dur != duration) {
        duration = dur;
        notifyListeners();
      }
    });
    _audioHandler.player.playerStateStream.listen((state) {
      if (state.playing != isPlaying) {
        isPlaying = state.playing;
        notifyListeners();
      }
    });
    _audioHandler.player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < queue.length) {
        final newTrack = queue[index];
        if (newTrack.id != currentTrack?.id) {
          currentIndex = index;
          currentTrack = newTrack;
          _updateDominantColor(newTrack.coverPath);
          _music.recordPlay(newTrack.id);
          notifyListeners();
        }
      }
    });
  }

  void pushOverlay(Widget screen) {
    if (_overlayStack.isNotEmpty) {
      final last = _overlayStack.last;
      if (last.runtimeType == screen.runtimeType) {
        if (last is ArtistScreen && screen is ArtistScreen) {
          if (last.artistName == screen.artistName) return;
        }
      }
    }
    _overlayStack.add(screen);
    notifyListeners();
  }

  void popOverlay() {
    if (_overlayStack.isNotEmpty) {
      _overlayStack.removeLast();
      notifyListeners();
    }
  }

  void clearOverlays() {
    _overlayStack.clear();
    notifyListeners();
  }

  Future<void> importTracks(List<String> filePaths) async {
    for (final path in filePaths) {
      final ext = p.extension(path).toLowerCase();
      if (['.mp3', '.flac', '.m4a', '.ogg', '.wav'].contains(ext)) {
        final track = await _music.parseFile(path);
        if (!_music.allTracks.any((t) => t.id == track.id)) {
          _music.addTrack(track);
        }
      }
    }
    _music.rebuildAlbums();
    await _music.saveToCache();
    notifyListeners();
  }

  void rebuildAlbums() => _music.rebuildAlbums();

  Future<void> initialize() async {
    await _auth.initialize();
    await _music.initialize();
    notifyListeners();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final hasAssets = _music.allTracks
          .any((t) => t.filePath?.startsWith('assets/') ?? false);
      if (!hasAssets) {
        await _music.scanAssetsMusic();
        if (!_isDisposed) notifyListeners();
      }
    });
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _audioHandler.player.dispose();
    super.dispose();
  }

  Future<void> scanMusic(String path) async {
    if (path.contains('assets')) {
      await _music.scanAssetsMusic();
    } else {
      await _music.scanDirectory(path);
    }
    notifyListeners();
  }

  Future<void> login(String name, String email) async {
    await _auth.login(name, email);
    notifyListeners();
  }

  Future<void> logout() async {
    await _audioHandler.stop();
    await _auth.logout();
    currentTrack = null;
    isPlaying = false;
    notifyListeners();
  }

  Future<void> playTrack(Track track, {List<Track>? trackList}) async {
    currentTrack = track;
    queue = trackList ?? [track];
    currentIndex = queue.indexWhere((t) => t.id == track.id);

    final items = queue
        .map((t) => MediaItem(
              id: t.filePath!,
              title: t.title,
              artist: t.artist,
              album: t.album,
              duration: t.duration,
              artUri: t.coverPath != null ? Uri.file(t.coverPath!) : null,
              extras: {'isAsset': t.filePath!.startsWith('assets/')},
            ))
        .toList();

    _updateDominantColor(track.coverPath);
    await _audioHandler.loadAndPlay(items, currentIndex);
    isPlaying = true;
    await _music.recordPlay(track.id);
  }

  void togglePlayPause() {
    if (isPlaying) {
      _audioHandler.pause();
    } else {
      _audioHandler.play();
    }
    isPlaying = !isPlaying;
    notifyListeners();
  }

  void nextTrack() {
    _audioHandler.skipToNext();
  }

  void previousTrack() {
    _audioHandler.skipToPrevious();
  }

  void seek(Duration pos) {
    _audioHandler.seek(pos);
    notifyListeners();
  }

  Future<void> toggleLike(String trackId) async {
    await _music.toggleLike(trackId);
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    showSearchResults = query.isNotEmpty;
    if (query.isNotEmpty) {
      _music.addSearchQuery(query);
    }
    notifyListeners();
  }

  void clearSearch() {
    searchQuery = '';
    showSearchResults = false;
    notifyListeners();
  }

  Future<void> createPlaylist(String name) async {
    await _music.createPlaylist(name);
    notifyListeners();
  }

  Future<void> addToPlaylist(String playlistId, String trackId) async {
    await _music.addToPlaylist(playlistId, trackId);
    notifyListeners();
  }

  void setTab(int index) {
    currentTab = index;
    notifyListeners();
  }

  Future<void> removeSearchQuery(String query) async {
    await _music.removeSearchQuery(query);
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    await _music.clearSearchHistory();
    notifyListeners();
  }

  Future<void> rescanCoversForExistingTracks() async {
    await _music.rescanCoversForExistingTracks();
    notifyListeners();
  }

  void setMissingTracks(List<Map<String, String>> tracks) {
    _missingTracks = tracks;
    notifyListeners();
  }

  void clearMissingTracks() {
    _missingTracks = [];
    notifyListeners();
  }

  Future<Color?> _extractDominantColor(String? coverPath) async {
    if (coverPath == null) return null;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        FileImage(File(coverPath)),
        size: const Size(50, 50), // réduit pour accélérer
      );
      return palette.dominantColor?.color;
    } catch (_) {
      return null;
    }
  }

  void _updateDominantColor(String? coverPath) {
    if (coverPath == null) {
      dominantColor = null;
      notifyListeners();
      return;
    }
    if (_colorCache.containsKey(coverPath)) {
      dominantColor = _colorCache[coverPath];
      notifyListeners();
      return;
    }
    final requestId = ++_lastColorRequest;
    _extractDominantColor(coverPath).then((color) {
      if (_isDisposed) return; // FIX: garde anti-crash
      if (requestId == _lastColorRequest && color != null) {
        _colorCache[coverPath] = color;
        dominantColor = color;
        notifyListeners();
      }
    });
  }
}
