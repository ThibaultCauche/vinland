import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:image/image.dart' as img;
import '../models/track.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../services/music_service.dart';
import '../services/auth_service.dart';
import '../services/audio_handler.dart';
import '../screens/artist_screen.dart';
import 'package:path/path.dart' as p;
import 'package:just_audio/just_audio.dart';
import '../services/navidrome_service.dart';
import '../models/vinland_user.dart';
import '../services/search_history_service.dart';
import 'package:http/http.dart' as http;

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

  // Getters
  List<Track> get allTracks => _music.navidromeTracks;
  List<Track> get likedTracks {
    final tracks = List<Track>.from(_music.likedTracks);
    tracks.sort((a, b) {
      if (a.dateAdded == null && b.dateAdded == null) return 0;
      if (a.dateAdded == null) return 1;
      if (b.dateAdded == null) return -1;
      return b.dateAdded!.compareTo(a.dateAdded!);
    });
    return tracks;
  }

  List<Track> get searchResults {
    if (searchQuery.isEmpty) return [];
    return _music.searchTracks(searchQuery);
  }

  bool get isLoggedIn => _auth.isLoggedIn;
  String? get userName => _auth.userName;
  String? get userEmail => _auth.userEmail;
  List<Album> get albums => _music.albums;
  MusicService get musicService => _music;
  bool get isLocalMode => false;
  Color? dominantColor;

  // Overlay navigation
  final List<Widget> _overlayStack = [];
  List<Widget> get overlayStack => List.unmodifiable(_overlayStack);
  Widget? get currentOverlay =>
      _overlayStack.isNotEmpty ? _overlayStack.last : null;

  // DEBOUNCE : absorbe les notify en rafale
  Timer? _notifyDebounce;

  // Expose le player pour les widgets (MiniPlayer, PlayerScreen)
  AudioPlayer get player => _audioHandler.player;

  // Delegue la verification de cover au MusicService
  bool coverExists(String? path) => _music.coverExists(path);

  //navidrome
  final NavidromeService _navidrome = NavidromeService();
  bool _useNavidrome = true;
  bool get useNavidrome => _useNavidrome;

  //lecture aléatoire
  bool get isShuffled => _audioHandler.isShuffled;
  LoopMode get loopMode => _audioHandler.loopMode;

  AppState({required VinlandAudioHandler audioHandler})
      : _audioHandler = audioHandler {
    _audioHandler.customActionStream.listen((action) {
      if (action == 'add_to_likes' && currentTrack != null) {
        toggleLike(currentTrack!.id);
      }
    });

    // Position : throttle a 500ms + debounce global
    _audioHandler.player.positionStream.listen((pos) {
      position = pos;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastPositionNotify > 500) {
        _lastPositionNotify = now;
        _notify();
      }
    });
    _audioHandler.player.durationStream.listen((dur) {
      if (dur != null && dur != duration) {
        duration = dur;
        _notify();
      }
    });
    _audioHandler.player.playerStateStream.listen((state) {
      if (state.playing != isPlaying) {
        isPlaying = state.playing;
        _notify();
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
          _notify();
        }
      }
    });
  }

  /// Un seul notifyListeners() au bout de 50ms, meme s'il y en a 10 d'affilee
  void _notify() {
    _notifyDebounce?.cancel();
    _notifyDebounce = Timer(const Duration(milliseconds: 50), () {
      if (!_isDisposed) notifyListeners();
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
    _notify();
  }

  void popOverlay() {
    if (_overlayStack.isNotEmpty) {
      _overlayStack.removeLast();
      _notify();
    }
  }

  void clearOverlays() {
    _overlayStack.clear();
    _notify();
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
    _notify();
  }

  void rebuildAlbums() => _music.rebuildAlbums();

  Future<void> initialize() async {
    await _auth.initialize();
    if (_auth.currentUser != null) {
      _music.setCurrentUser(_auth.currentUser!.id);
    }
    await _music.initialize();
    _useNavidrome = _music.navidromeTracks.isNotEmpty;
    _notify();

    final navidromeOk = await _navidrome.loadCredentials();
    if (navidromeOk) {
      _music.syncWithNavidrome().then((_) {
        _useNavidrome = _music.navidromeTracks.isNotEmpty;
        _notify();
      });
    }
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _notifyDebounce?.cancel();
    _audioHandler.player.dispose();
    super.dispose();
  }

  Future<void> scanMusic(String path) async {
    if (path.contains('assets')) {
      await _music.scanAssetsMusic();
    } else {
      await _music.scanDirectory(path);
    }
    _notify();
  }

  Future<bool> login(String email, String password) async {
    final success = await _auth.login(email, password);
    if (success && _auth.currentUser != null) {
      _music.setCurrentUser(_auth.currentUser!.id);
      SearchHistoryService().setCurrentUser(_auth.currentUser!.id);
      _music.initialize();
    }
    _notify();
    return success;
  }

  Future<VinlandUser?> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    final user = await _auth.register(
      firstName: firstName,
      lastName: lastName,
      email: email,
      password: password,
    );
    _notify();
    return user;
  }

  VinlandUser? get currentUser => _auth.currentUser;
  bool get isAdmin => _auth.isAdmin;

  Future<void> logout() async {
    await _audioHandler.stop();
    await _auth.logout();
    _music.setCurrentUser(null);
    SearchHistoryService().setCurrentUser(null);
    currentTrack = null;
    isPlaying = false;
    _notify();
  }

  Future<void> playTrack(Track track, {List<Track>? trackList}) async {
    currentTrack = track;
    queue = trackList ?? [track];
    currentIndex = queue.indexWhere((t) => t.id == track.id);

    final items = queue.map((t) {
      final path = _music.getOfflinePath(t.id) ?? t.filePath!;
      final isAsset = path.startsWith('assets/');
      final isRemote = path.startsWith('http');

      Uri? artUri;
      if (t.coverPath != null) {
        artUri = t.coverPath!.startsWith('http')
            ? Uri.parse(t.coverPath!)
            : Uri.file(t.coverPath!);
      }

      return MediaItem(
        id: path,
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: t.duration,
        artUri: artUri,
        extras: {'isAsset': isAsset, 'isRemote': isRemote},
      );
    }).toList();

    _updateDominantColor(track.coverPath);
    _notify();
    await Future.delayed(Duration.zero);
    await _audioHandler.loadAndPlay(items, currentIndex);
    isPlaying = true;
    await _music.recordPlay(track.id);
    _notify();
  }

  void togglePlayPause() {
    if (isPlaying) {
      _audioHandler.pause();
    } else {
      _audioHandler.play();
    }
    isPlaying = !isPlaying;
    _notify();
  }

  void nextTrack() {
    _audioHandler.skipToNext();
  }

  void previousTrack() {
    _audioHandler.skipToPrevious();
  }

  void seek(Duration pos) {
    _audioHandler.seek(pos);
    _notify();
  }

  Future<void> toggleLike(String trackId) async {
    await _music.toggleLike(trackId);
    _notify();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    showSearchResults = query.isNotEmpty;
    _notify();
  }

  void clearSearch() {
    searchQuery = '';
    showSearchResults = false;
    _notify();
  }

  Future<void> createPlaylist(String name) async {
    await _music.createPlaylist(name);
    _notify();
  }

  Future<void> addToPlaylist(String playlistId, String trackId) async {
    await _music.addToPlaylist(playlistId, trackId);
    _notify();
  }

  void setTab(int index) {
    currentTab = index;
    _notify();
  }

  Future<void> rescanCoversForExistingTracks() async {
    await _music.rescanCoversForExistingTracks();
    _notify();
  }

  List<Map<String, dynamic>> get missingTracks => _music.missingTracks;

  void setMissingTracks(List<Map<String, dynamic>> tracks) {
    _music.setMissingTracks(tracks);
    _notify();
  }

  void clearMissingTracks() {
    _music.clearMissingTracks();
    _notify();
  }

  List<Album> get likedAlbums => _music.likedAlbums;
  List<Playlist> get playlists => _music.playlists;

  Future<void> toggleLikeAlbum(String albumId) async {
    await _music.toggleLikeAlbum(albumId);
    _notify();
  }

  /// Extrait la couleur dominante dans un isolate — ZERO blocage UI
  Future<Color?> _extractDominantColorIsolate(String coverPath) async {
    try {
      Uint8List bytes;
      if (coverPath.startsWith('http')) {
        final response = await http.get(Uri.parse(coverPath));
        if (response.statusCode != 200) return null;
        bytes = response.bodyBytes;
      } else {
        bytes = await File(coverPath).readAsBytes();
      }
      return await compute(_dominantColorFromBytes, bytes);
    } catch (_) {
      return null;
    }
  }

  /// Cette fonction tourne dans un isolate separe
  static Color? _dominantColorFromBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final w = decoded.width;
    final h = decoded.height;

    final samples = [
      decoded.getPixel(w ~/ 2, h ~/ 2),
      decoded.getPixel(w ~/ 4, h ~/ 4),
      decoded.getPixel(w * 3 ~/ 4, h ~/ 4),
      decoded.getPixel(w ~/ 4, h * 3 ~/ 4),
      decoded.getPixel(w * 3 ~/ 4, h * 3 ~/ 4),
    ];

    int r = 0, g = 0, b = 0;
    for (final p in samples) {
      final pixel = p as dynamic;
      r += (pixel.r as num).round();
      g += (pixel.g as num).round();
      b += (pixel.b as num).round();
    }

    return Color.fromRGBO(
      r ~/ samples.length,
      g ~/ samples.length,
      b ~/ samples.length,
      1,
    );
  }

  void _updateDominantColor(String? coverPath) {
    if (coverPath == null) {
      print('PALETTE: coverPath null');
      dominantColor = null;
      _notify();
      return;
    }
    if (_colorCache.containsKey(coverPath)) {
      print('PALETTE: cache hit');
      dominantColor = _colorCache[coverPath];
      _notify();
      return;
    }
    final requestId = ++_lastColorRequest;
    print('PALETTE: start extraction (isolate)');
    _extractDominantColorIsolate(coverPath).then((color) {
      if (_isDisposed) return;
      print('PALETTE: done, color=$color');
      if (requestId == _lastColorRequest && color != null) {
        _colorCache[coverPath] = color;
        dominantColor = color;
        _notify();
      }
    });
  }

  Future<void> setNavidromeMode(bool enabled) async {
    _useNavidrome = enabled;
    if (enabled && !_navidrome.isConnected) {
      final ok = await _navidrome.loadCredentials();
      if (ok) await _music.syncWithNavidrome();
    }
    _notify();
  }

  Future<bool> configureNavidrome(String url, String user, String pass) async {
    final ok = await _navidrome.saveCredentials(url, user, pass);
    if (ok) {
      await _music.syncWithNavidrome();
      _useNavidrome = true;
    }
    _notify();
    return ok;
  }

  Future<void> syncNavidrome() async {
    await _music.syncWithNavidrome();
    _notify();
  }

  Future<void> downloadTrackOffline(Track track) async {
    await _music.downloadTrack(track);
    _notify();
  }

  bool isTrackOffline(String trackId) => _music.isTrackDownloaded(trackId);

  void toggleShuffle() {
    _audioHandler.toggleShuffle();
    _notify();
  }

  void toggleLoopMode() {
    final next = {
      LoopMode.off: LoopMode.all,
      LoopMode.all: LoopMode.one,
      LoopMode.one: LoopMode.off,
    }[_audioHandler.loopMode]!;
    _audioHandler.setLoopMode(next);
    _notify();
  }
}
