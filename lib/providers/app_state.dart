import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/music_service.dart';
import '../services/auth_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/album.dart';
import '../screens/artist_screen.dart';
import 'package:path/path.dart' as p;
import '../services/api_service.dart';

class AppState extends ChangeNotifier {
  final MusicService _music = MusicService();
  final AuthService _auth = AuthService();
  final AudioPlayer _player = AudioPlayer();
  final ApiService _api = ApiService();

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
  List<Track> get allTracks => _api.useLocal ? _music.allTracks : [];
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
  bool get isLocalMode => _api.useLocal;

  // Overlay navigation
  final List<Widget> _overlayStack = [];
  List<Widget> get overlayStack => List.unmodifiable(_overlayStack);
  Widget? get currentOverlay =>
      _overlayStack.isNotEmpty ? _overlayStack.last : null;

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

  void switchMode(bool local) {
    _api.useLocal = local;
    notifyListeners();
  }

  Future<void> importTracks(List<String> filePaths) async {
    for (final path in filePaths) {
      final ext = p.extension(path).toLowerCase();
      if (ext == '.mp3' ||
          ext == '.flac' ||
          ext == '.m4a' ||
          ext == '.ogg' ||
          ext == '.wav') {
        final track = await _music.parseFile(path);
        if (!_music.allTracks.any((t) => t.id == track.id)) {
          // Track déjà géré dans MusicService via parseFile + rebuildAlbums
        }
      }
    }
    _music.rebuildAlbums();
    notifyListeners();
  }

  void rebuildAlbums() => _music.rebuildAlbums();

  void popOverlay() {
    if (_overlayStack.isNotEmpty) {
      _overlayStack.removeLast();
      notifyListeners();
    }
  }

  AppState() {
    _player.positionStream.listen((pos) {
      position = pos;
      notifyListeners();
    });
    _player.durationStream.listen((dur) {
      if (dur != null) {
        duration = dur;
        notifyListeners();
      }
    });
    _player.playerStateStream.listen((state) {
      isPlaying = state.playing;
      notifyListeners();
    });
  }

  void addSearchQuery(String query) {
    if (query.isNotEmpty) {
      _music.addSearchQuery(query);
      notifyListeners();
    }
  }

  Future initialize() async {
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
    await _auth.logout();
    currentTrack = null;
    isPlaying = false;
    notifyListeners();
  }

  Future<void> playTrack(Track track, {List<Track>? trackList}) async {
    currentTrack = track;
    queue = trackList ?? [track];
    currentIndex = queue.indexWhere((t) => t.id == track.id);

    try {
      if (track.filePath != null && track.filePath!.startsWith('assets/')) {
        await _player.setAudioSource(AudioSource.asset(track.filePath!));
      } else if (track.filePath != null) {
        await _player.setFilePath(track.filePath!);
      }
      await _player.play();
      isPlaying = true;
    } catch (e) {
      print('ERREUR LECTURE: $e');
      isPlaying = false;
    }

    _music.recordPlay(track.id);
    notifyListeners();
  }

  void togglePlayPause() {
    if (isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
    isPlaying = !isPlaying;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void nextTrack() {
    if (currentIndex < queue.length - 1) {
      currentIndex++;
      currentTrack = queue[currentIndex];
      _music.recordPlay(currentTrack!.id);
      notifyListeners();
    }
  }

  void previousTrack() {
    if (currentIndex > 0) {
      currentIndex--;
      currentTrack = queue[currentIndex];
      _music.recordPlay(currentTrack!.id);
      notifyListeners();
    }
  }

  void seek(Duration pos) {
    _player.seek(pos);
    notifyListeners();
  }

  void updatePosition(Duration pos, Duration dur) {
    position = pos;
    duration = dur;
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

  void clearOverlays() {
    _overlayStack.clear();
    notifyListeners();
  }

  Future rescanCoversForExistingTracks() async {
    await _music.rescanCoversForExistingTracks();
    notifyListeners();
  }
}
