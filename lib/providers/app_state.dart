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
import '../models/friend_profile.dart';
import '../services/music_service.dart';
import '../services/audio_handler.dart';
import '../screens/artist_screen.dart';
import 'package:path/path.dart' as p;
import '../services/player_engine.dart';
import '../services/navidrome_service.dart';
import '../services/secure_storage.dart';
import '../models/recent_play.dart';
import '../services/search_history_service.dart';
import '../services/update_check_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  final MusicService _music = MusicService();
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

  // "Reste connecte" par defaut : une fois des identifiants sauvegardes, on
  // n'affiche plus l'ecran de connexion meme si le dernier ping en direct a
  // echoue (NAS/Tailscale Funnel temporairement lent ou injoignable) -- la
  // bibliotheque en cache s'affiche, la resynchro se fait en fond des que
  // le serveur redevient joignable. Seule une deconnexion explicite
  // ramene a l'ecran de connexion.
  bool get isLoggedIn => _navidrome.hasCredentials;
  String? get userName => _navidrome.username;
  String? get navidromeUrl => _navidrome.baseUrl;
  String? get currentUserId => _navidrome.username;
  List<Album> get albums => _music.albums;
  MusicService get musicService => _music;
  bool get isLocalMode => false;
  Color? dominantColor;

  // Vrai tant que le tout premier chargement (cache local + tentative de
  // connexion Navidrome) n'est pas termine : evite un flash de l'ecran de
  // connexion (ou un "mot de passe incorrect" trompeur) le temps que le ping
  // reseau vers le NAS reponde, ce qui peut prendre plusieurs secondes.
  bool _isInitializing = true;
  bool get isInitializing => _isInitializing;

  // Overlay navigation
  final List<Widget> _overlayStack = [];
  List<Widget> get overlayStack => List.unmodifiable(_overlayStack);
  Widget? get currentOverlay =>
      _overlayStack.isNotEmpty ? _overlayStack.last : null;

  // DEBOUNCE : absorbe les notify en rafale
  Timer? _notifyDebounce;

  // Expose le player pour les widgets (MiniPlayer, PlayerScreen)
  PlayerEngine get player => _audioHandler.player;

  // Delegue la verification de cover au MusicService
  bool coverExists(String? path) => _music.coverExists(path);

  //navidrome
  final NavidromeService _navidrome = NavidromeService();
  bool _useNavidrome = true;
  bool get useNavidrome => _useNavidrome;

  //lecture aléatoire
  bool get isShuffled => _audioHandler.isShuffled;
  LoopMode get loopMode => _audioHandler.loopMode;

  // Telechargement automatique des titres/albums/playlists likes
  static const _keyAutoDownloadLikes = 'vinland_auto_download_likes';
  bool _autoDownloadLikes = false;
  bool get autoDownloadLikes => _autoDownloadLikes;

  // Derniere lecture (mini-player) + lecture aleatoire/repetition :
  // memorises pour survivre a un redemarrage de l'app.
  static const _keyLastTrackId = 'vinland_last_track_id';
  static const _keyLastQueueIds = 'vinland_last_queue_ids';
  static const _keyLastQueueIndex = 'vinland_last_queue_index';
  static const _keyShuffleEnabled = 'vinland_shuffle_enabled';
  static const _keyLoopMode = 'vinland_loop_mode';
  bool get isRepeatEnabled => loopMode != LoopMode.off;

  Future<void> setAutoDownloadLikes(bool value) async {
    _autoDownloadLikes = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoDownloadLikes, value);
    _notify();
  }

  AppState({required VinlandAudioHandler audioHandler})
      : _audioHandler = audioHandler {
    _audioHandler.customActionStream.listen((action) {
      if (action == 'add_to_likes' && currentTrack != null) {
        toggleLike(currentTrack!.id);
      }
    });

    // Position : mise a jour du champ pour compat, SANS notifyListeners().
    // Rien dans l'UI ne lit state.position (MiniPlayer/PlayerSlider pollent
    // le player directement) : notifier ici reconstruisait TOUS les ecrans
    // abonnes a AppState ~2x/seconde pendant la lecture, pour rien.
    _audioHandler.player.positionStream.listen((pos) {
      position = pos;
    });
    _audioHandler.player.durationStream.listen((dur) {
      if (dur != null && dur != duration) {
        duration = dur;
        _notify();
      }
    });
    _audioHandler.player.playingStream.listen((playing) {
      if (playing != isPlaying) {
        isPlaying = playing;
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

    // File terminee (dernier titre fini, pas de boucle) : au lieu de couper
    // brutalement, on enchaine sur des titres du meme artiste puis, a
    // defaut, les titres les plus ecoutes de la bibliotheque.
    _audioHandler.player.completedStream.listen((_) {
      _continueQueueAutomatically();
    });
  }

  bool _autoContinuing = false;

  Future<void> _continueQueueAutomatically() async {
    if (_autoContinuing || _isDisposed) return;
    if (loopMode != LoopMode.off) return; // l'utilisateur boucle deja
    if (queue.isEmpty) return;

    _autoContinuing = true;
    try {
      final next = _buildContinuationQueue();
      if (next.isNotEmpty) {
        await playTrack(next.first, trackList: next);
      }
    } finally {
      _autoContinuing = false;
    }
  }

  /// Titres du meme artiste (non deja ecoutes dans la file qui vient de
  /// finir) en priorite, sinon les titres les plus ecoutes de la
  /// bibliotheque, pour eviter une coupure brutale de la lecture.
  List<Track> _buildContinuationQueue() {
    final playedIds = queue.map((t) => t.id).toSet();
    final artist = currentTrack?.artist;

    var pool = artist == null
        ? <Track>[]
        : _music.allTracks
            .where((t) => t.artist == artist && !playedIds.contains(t.id))
            .toList();

    if (pool.isEmpty) {
      pool = _music.allTracks.where((t) => !playedIds.contains(t.id)).toList();
    }

    pool.sort((a, b) => b.playCount.compareTo(a.playCount));
    return pool.take(20).toList();
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
    final prefs = await SharedPreferences.getInstance();
    _autoDownloadLikes = prefs.getBool(_keyAutoDownloadLikes) ?? false;

    // Pre-charge le dernier nom d'utilisateur Navidrome connu (lecture locale,
    // pas de reseau) pour scoper le cache musical AVANT l'authentification :
    // celle-ci peut prendre jusqu'a 10s si le NAS est lent/injoignable, et la
    // bibliotheque locale ne doit pas attendre le reseau pour s'afficher.
    final savedUsername = (await SecureStorage.getCredentials())['username'];
    if (savedUsername != null && savedUsername.isNotEmpty) {
      _music.setCurrentUser(savedUsername);
      SearchHistoryService().setCurrentUser(savedUsername);
    }
    await _music.initialize();
    _useNavidrome = _music.navidromeTracks.isNotEmpty;
    await _restorePlaybackState(prefs);

    // Rien de plus a attendre pour afficher l'app : "rester connecte" veut
    // dire ne jamais bloquer l'affichage (ni l'ecran de connexion) sur un
    // ping reseau. La reconnexion/resynchro Navidrome se fait en fond.
    _isInitializing = false;
    _notify();

    unawaited(_navidrome.loadCredentials().then((navidromeOk) {
      if (navidromeOk) {
        _music.syncWithNavidrome().then((_) {
          _useNavidrome = _music.navidromeTracks.isNotEmpty;
          _notify();
        });
      } else {
        _notify();
      }
    }));

    unawaited(checkForUpdate());
  }

  UpdateInfo? updateInfo;

  Future<void> checkForUpdate() async {
    updateInfo = await UpdateCheckService().checkForUpdate();
    if (updateInfo != null) _notify();
  }

  /// Recharge le dernier titre joue (pour l'affichage dans le mini-player,
  /// sans relancer la lecture automatiquement) ainsi que les modes lecture
  /// aleatoire/repetition, a partir du cache local deja charge par
  /// `_music.initialize()` (pas besoin d'attendre la sync Navidrome).
  Future<void> _restorePlaybackState(SharedPreferences prefs) async {
    final shuffle = prefs.getBool(_keyShuffleEnabled) ?? false;
    if (shuffle) await _audioHandler.player.setShuffleModeEnabled(true);
    final loopName = prefs.getString(_keyLoopMode);
    if (loopName != null) {
      final mode = LoopMode.values
          .firstWhere((m) => m.name == loopName, orElse: () => LoopMode.off);
      await _audioHandler.setLoopMode(mode);
    }

    final lastTrackId = prefs.getString(_keyLastTrackId);
    if (lastTrackId == null) return;
    final track = _findTrackById(lastTrackId);
    if (track == null) return;

    final queueIds = prefs.getStringList(_keyLastQueueIds) ?? [lastTrackId];
    final restoredQueue =
        queueIds.map(_findTrackById).whereType<Track>().toList();
    queue = restoredQueue.isNotEmpty ? restoredQueue : [track];
    currentIndex = queue.indexWhere((t) => t.id == track.id);
    if (currentIndex < 0) currentIndex = 0;
    currentTrack = track;
    _updateDominantColor(track.coverPath);
    // isPlaying reste false : on affiche juste le dernier titre, on ne
    // relance pas un flux reseau tant que l'utilisateur n'a pas appuye play.
  }

  Future<void> _savePlaybackState() async {
    if (currentTrack == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastTrackId, currentTrack!.id);
    await prefs.setStringList(
        _keyLastQueueIds, queue.map((t) => t.id).toList());
    await prefs.setInt(_keyLastQueueIndex, currentIndex);
  }

  Future<void> _saveShuffleLoopState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShuffleEnabled, isShuffled);
    await prefs.setString(_keyLoopMode, loopMode.name);
  }

  Future<void> _clearPlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastTrackId);
    await prefs.remove(_keyLastQueueIds);
    await prefs.remove(_keyLastQueueIndex);
    await prefs.remove(_keyShuffleEnabled);
    await prefs.remove(_keyLoopMode);
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

  Future<void> logout() async {
    // La coupure du lecteur passe par un canal de plateforme (audio_service) :
    // si le service audio est dans un mauvais etat (ex: coupure reseau au NAS,
    // foreground service tue par l'OS), cet appel peut planter ou rester
    // bloque indefiniment. On ne doit jamais laisser ca empecher la
    // deconnexion : on le tente avec un timeout, sans jamais propager d'erreur.
    try {
      await _audioHandler.stop().timeout(const Duration(seconds: 2));
    } catch (e) {
      print('logout: audioHandler.stop() a echoue/timeout: $e');
    }
    await _navidrome.clearCredentials();
    _music.setCurrentUser(null);
    SearchHistoryService().setCurrentUser(null);
    currentTrack = null;
    isPlaying = false;
    queue = [];
    currentIndex = -1;
    await _clearPlaybackState();
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
    unawaited(_savePlaybackState());
    _notify();
  }

  void togglePlayPause() {
    // Redemarrage de l'app : le mini-player affiche le dernier titre joue
    // mais aucune source audio n'a encore ete chargee dans le player. Un
    // simple play()/pause() sur un player vide ne fait rien : il faut
    // relancer une vraie lecture via playTrack().
    if (currentTrack != null && !_audioHandler.player.hasSource) {
      playTrack(currentTrack!, trackList: queue.isNotEmpty ? queue : null);
      return;
    }
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

  Track? _findTrackById(String id) {
    for (final t in _music.allTracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> toggleLike(String trackId) async {
    await _music.toggleLike(trackId);
    if (_autoDownloadLikes) {
      final track = _findTrackById(trackId);
      if (track != null && track.isLiked) {
        unawaited(downloadTrackOffline(track));
      }
    }
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
    if (_autoDownloadLikes) {
      final track = _findTrackById(trackId);
      if (track != null) {
        unawaited(downloadTrackOffline(track));
      }
    }
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

  // AMIS : liste construite a partir des playlists publiques des autres
  // utilisateurs du serveur (voir MusicService.fetchFriends). Rechargee a la
  // demande (ouverture de l'onglet Amis), pas en continu.
  List<FriendProfile> friends = [];
  bool loadingFriends = false;

  Future<void> loadFriends() async {
    loadingFriends = true;
    _notify();
    friends = await _music.fetchFriends();
    loadingFriends = false;
    _notify();
  }

  bool get shareLikesWithFriends => _music.shareLikesWithFriends;

  Future<void> setShareLikesWithFriends(bool value) async {
    await _music.setShareLikesWithFriends(value);
    _notify();
  }

  Future<void> setPlaylistPublic(String playlistId, bool public) async {
    await _music.setPlaylistPublic(playlistId, public);
    _notify();
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _music.deletePlaylist(playlistId);
    _notify();
  }

  /// 6 dernier(e)s album/playlist/artiste ecoute(e)s, comme sur Spotify.
  List<RecentPlay> get recentPlays => _music.recentPlays.take(6).toList();

  void recordRecentPlay(RecentPlay entry) {
    _music.recordRecentPlay(entry);
    _notify();
  }

  Future<void> toggleLikeAlbum(String albumId) async {
    await _music.toggleLikeAlbum(albumId);
    if (_autoDownloadLikes) {
      final matches = _music.albums.where((a) => a.id == albumId);
      if (matches.isNotEmpty && matches.first.isSaved) {
        final trackIds = matches.first.trackIds.toSet();
        final tracks =
            _music.allTracks.where((t) => trackIds.contains(t.id)).toList();
        unawaited(downloadTracksOffline(tracks));
      }
    }
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

  /// Point d'entree unique pour se connecter/reconnecter a Navidrome, que ce
  /// soit depuis l'ecran de connexion (premiere connexion) ou depuis
  /// Parametres (changement de serveur) : la connexion Vinland EST la
  /// connexion Navidrome, il n'y a plus de compte Vinland separe.
  Future<bool> configureNavidrome(String url, String user, String pass) async {
    final ok = await _navidrome.saveCredentials(url, user, pass);
    if (ok) {
      _music.setCurrentUser(_navidrome.username);
      SearchHistoryService().setCurrentUser(_navidrome.username);
      await _music.initialize();
      _useNavidrome = _music.navidromeTracks.isNotEmpty;
      // La synchro complete (des centaines d'albums) peut prendre longtemps :
      // on ne bloque pas l'ecran de connexion dessus, elle continue en fond
      // une fois que l'utilisateur est deja entre dans l'app.
      unawaited(_music.syncWithNavidrome().then((_) {
        _useNavidrome = _music.navidromeTracks.isNotEmpty;
        _notify();
      }));
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

  bool areTracksOffline(List<Track> tracks) => _music.areAllDownloaded(tracks);

  Future<void> downloadTracksOffline(
    List<Track> tracks, {
    void Function(double progress)? onProgress,
  }) async {
    await _music.downloadTracks(tracks, onProgress: (p) {
      onProgress?.call(p);
      _notify();
    });
    _notify();
  }

  Future<void> removeDownloads(List<Track> tracks) async {
    await _music.removeDownloads(tracks);
    _notify();
  }

  Future<void> toggleShuffle() async {
    await _audioHandler.toggleShuffle();
    unawaited(_saveShuffleLoopState());
    _notify();
  }

  Future<void> toggleLoopMode() async {
    final next = {
      LoopMode.off: LoopMode.all,
      LoopMode.all: LoopMode.one,
      LoopMode.one: LoopMode.off,
    }[_audioHandler.loopMode]!;
    await _audioHandler.setLoopMode(next);
    unawaited(_saveShuffleLoopState());
    _notify();
  }

  Future<void> clearAllLikes() async {
    await _music.clearAllLikes();
    _notify();
  }
}
