import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/track.dart';
import '../services/music_service.dart';
import '../services/auth_service.dart';
import '../services/audio_handler.dart';
import '../models/album.dart';
import '../screens/artist_screen.dart';
import 'package:path/path.dart' as p;

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

  // UI state
  int currentTab = 0;
  String searchQuery = '';
  bool showSearchResults = false;

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

  // Overlay navigation
  final List<Widget> _overlayStack = [];
  List<Widget> get overlayStack => List.unmodifiable(_overlayStack);
  Widget? get currentOverlay =>
      _overlayStack.isNotEmpty ? _overlayStack.last : null;

  AppState({required VinlandAudioHandler audioHandler})
      : _audioHandler = audioHandler {
    _audioHandler.player.positionStream.listen((pos) {
      position = pos;
      notifyListeners();
    });
    _audioHandler.player.durationStream.listen((dur) {
      if (dur != null) {
        duration = dur;
        notifyListeners();
      }
    });
    _audioHandler.player.playerStateStream.listen((state) {
      isPlaying = state.playing;
      notifyListeners();
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
        notifyListeners();
      }
    });
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

    await _audioHandler.loadAndPlay(items, currentIndex);
    isPlaying = true;

    _music.recordPlay(track.id);
    notifyListeners();
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
    final index = _audioHandler.player.currentIndex ?? currentIndex;
    if (index >= 0 && index < queue.length) {
      currentIndex = index;
      currentTrack = queue[index];
      _music.recordPlay(currentTrack!.id);
      notifyListeners();
    }
  }

  void previousTrack() {
    _audioHandler.skipToPrevious();
    final index = _audioHandler.player.currentIndex ?? currentIndex;
    if (index >= 0 && index < queue.length) {
      currentIndex = index;
      currentTrack = queue[index];
      _music.recordPlay(currentTrack!.id);
      notifyListeners();
    }
  }

  void seek(Duration pos) {
    _audioHandler.seek(pos);
    notifyListeners();
  }

  void toggleLike(String trackId) {
    _music.toggleLike(trackId);
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

  void createPlaylist(String name) {
    _music.createPlaylist(name);
    notifyListeners();
  }

  void addToPlaylist(String playlistId, String trackId) {
    _music.addToPlaylist(playlistId, trackId);
    notifyListeners();
  }

  void setTab(int index) {
    currentTab = index;
    notifyListeners();
  }

  void removeSearchQuery(String query) {
    _music.removeSearchQuery(query);
    notifyListeners();
  }

  void clearSearchHistory() {
    _music.clearSearchHistory();
    notifyListeners();
  }

  Future<void> rescanCoversForExistingTracks() async {
    await _music.rescanCoversForExistingTracks();
    notifyListeners();
  }

  @override
  void dispose() {
    _audioHandler.player.dispose();
    super.dispose();
  }
}
