import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:image/image.dart' as img;
import '../models/track.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../models/friend_profile.dart';
import '../models/collab_playlist.dart';
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
import '../services/jam_service.dart';
import '../services/avatar_service.dart';
import '../desktop/desktop_theme.dart';
import '../theme/mobile_theme.dart';
import '../theme/solid_color_effect.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  final MusicService _music = MusicService();
  final VinlandAudioHandler _audioHandler;
  final JamService _jam = JamService();

  bool get isJamActive => _jam.isActive;
  bool get isJamHost => _jam.isHost;
  String? get jamSessionId => _jam.sessionId;
  int jamParticipantCount = 0;
  StreamSubscription? _jamStateSub;
  StreamSubscription? _jamHostLeftSub;
  StreamSubscription? _jamCountSub;
  Timer? _jamHeartbeat;
  bool _applyingJamState = false;

  // Player state
  Track? currentTrack;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  // File d'attente ("Titres a venir") : les titres qui vont suivre, dans
  // l'ordre d'ecoute -- visible/reordonnable par l'utilisateur (voir
  // QueueScreen), completee par "Ajouter a la file d'attente". Ne contient
  // JAMAIS le titre en cours (currentTrack) : contrairement a l'ancien
  // design, un seul titre a la fois est charge dans le moteur audio (voir
  // _playSingle) -- next/previous/shuffle sont geres ici, pas delegues au
  // shuffle natif de just_audio/mpv (source du bug ou le titre affiche
  // desynchronisait du titre reellement joue, et ou le tout premier titre de
  // "Titres likes" revenait bien plus souvent que les autres a chaque fin de
  // cycle melange).
  List<Track> queue = [];
  // Ordre d'origine de la collection lancee (album/playlist/titres likes/
  // artiste) : sert a regenerer `queue` quand on (re)active le mode
  // aleatoire ou quand la file est epuisee (on reboucle sur ce meme
  // contexte plutot que de s'arreter net, cf. retour des beta-testeurs).
  List<Track> _sourceOrder = [];
  // Titres deja joues cette session, pour le bouton "precedent". Bornee pour
  // ne pas grossir indefiniment sur une tres longue session d'ecoute.
  static const int _maxHistory = 200;
  final List<Track> _history = [];
  void _pushHistory(Track track) {
    _history.add(track);
    if (_history.length > _maxHistory) _history.removeAt(0);
  }

  int _lastColorRequest = 0;
  final Map<String, Color> _colorCache = {};

  // UI state
  int currentTab = 0;
  String searchQuery = '';
  bool showSearchResults = false;
  bool get isCurrentTrackLiked =>
      currentTrack != null &&
      _music.likedTracks.any((t) => t.id == currentTrack!.id);
  bool get isCurrentTrackSuperLiked =>
      currentTrack != null &&
      _music.likedTracks
          .any((t) => t.id == currentTrack!.id && t.superLiked);

  // Getters
  List<Track> get allTracks => _music.navidromeTracks;
  // MusicService.likedTracks trie deja par dateAdded (plus recent d'abord)
  // avec un tiebreak stable -- ne pas re-trier ici : un deuxieme List.sort
  // avec ex-aequo (meme date, ex: import CSV en lot) melangeait l'ordre a
  // chaque appel, le tri de Dart n'etant pas garanti stable.
  List<Track> get likedTracks => _music.likedTracks;

  /// Comme [likedTracks], mais avec en plus un titre "fantome" par entree de
  /// [missingTracks] (titre importe via CSV mais introuvable sur le NAS),
  /// intercale au bon endroit grace a la meme date synthetique que celle
  /// posee sur les titres retrouves au moment de l'import (voir
  /// StreamingMatchScreen._likeMatched) -- l'ordre affiche correspond ainsi a
  /// l'ordre du fichier importe, pistes manquantes comprises. A n'utiliser
  /// que pour l'affichage de la page "Titres likes" : ces titres fantomes
  /// n'ont pas de fichier reel (Track.isPlaceholder) et doivent etre exclus
  /// de toute file de lecture.
  List<Track> get likedTracksWithMissing {
    final placeholders = _music.missingTracks.map((m) {
      return Track(
        id: 'missing:${m['title']}:${m['artist']}:${m['album']}',
        title: (m['title'] ?? '').toString(),
        artist: (m['artist'] ?? '').toString(),
        album: (m['album'] ?? '').toString(),
        duration: Duration.zero,
        isLiked: true,
        dateAdded: DateTime.tryParse((m['dateAdded'] ?? '').toString()),
      );
    }).toList();

    final combined = [..._music.likedTracks, ...placeholders];
    combined.sort((a, b) {
      final da = a.dateAdded;
      final db = b.dateAdded;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return combined;
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

  // Etageres "suggestions" de l'accueil (Ecoutes cette semaine, Artistes du
  // moment, Decouverte, Nouveautes du NAS) : calculees une fois et mises en
  // cache ici plutot que recalculees a chaque build de HomeScreen/
  // DesktopHomeView a partir de allTracks/albums -- voir _refreshHomeShelves.
  List<Track> homeWeeklyTracks = [];
  List<(String artist, String? coverPath)> homeTopArtists = [];
  List<Album> homeDiscoveryAlbums = [];
  List<Album> homeNewOnServerAlbums = [];

  /// Recalcule les etageres "suggestions" de l'accueil. Volontairement PAS
  /// appele a chaque lot recu pendant une synchro (voir le garde dans
  /// _notify) : sinon, comme allTracks/albums grossissent en continu le
  /// temps que la synchro se termine, ces suggestions (notamment le melange
  /// aleatoire de "Decouverte", cense rester stable sur une journee)
  /// changeaient sans arret pendant tout le chargement au lieu de rester
  /// stables, remplacant ce qui etait deja affiche a l'utilisateur.
  void _refreshHomeShelves() {
    final tracks = allTracks;
    final albumsList = albums;

    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final recent = tracks
        .where((t) =>
            t.playCount > 0 &&
            t.lastPlayed != null &&
            t.lastPlayed!.isAfter(weekAgo))
        .toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    homeWeeklyTracks = recent.take(10).toList();

    final playsByArtist = <String, int>{};
    final coverByArtist = <String, String?>{};
    for (final t in tracks) {
      if (t.playCount <= 0) continue;
      playsByArtist.update(t.artist, (v) => v + t.playCount,
          ifAbsent: () => t.playCount);
      coverByArtist.putIfAbsent(t.artist, () => t.coverPath);
    }
    final artistNames = playsByArtist.keys.toList()
      ..sort((a, b) => playsByArtist[b]!.compareTo(playsByArtist[a]!));
    homeTopArtists =
        artistNames.take(10).map((a) => (a, coverByArtist[a])).toList();

    final tracksById = {for (final t in tracks) t.id: t};
    final notLiked = albumsList.where((a) {
      if (a.isSaved) return false;
      return a.trackIds.every((id) => tracksById[id]?.isLiked != true);
    }).toList();
    final today = DateTime.now();
    final seed = today.year * 10000 + today.month * 100 + today.day;
    homeDiscoveryAlbums =
        (List<Album>.of(notLiked)..shuffle(Random(seed))).take(10).toList();

    final withDate = albumsList.where((a) => a.addedToServerAt != null).toList()
      ..sort((a, b) => b.addedToServerAt!.compareTo(a.addedToServerAt!));
    homeNewOnServerAlbums = withDate.take(10).toList();
  }

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

  // Lecture aleatoire/repetition : geres ici (pas delegues au moteur audio,
  // qui ne charge plus qu'un seul titre a la fois -- voir _playSingle), pour
  // pouvoir melanger/reboucler notre propre file d'attente nous-memes.
  bool isShuffled = false;
  LoopMode loopMode = LoopMode.off;

  // Telechargement automatique des titres/albums/playlists likes
  static const _keyAutoDownloadLikes = 'vinland_auto_download_likes';
  bool _autoDownloadLikes = false;
  bool get autoDownloadLikes => _autoDownloadLikes;

  // Derniere lecture (mini-player) + lecture aleatoire/repetition :
  // memorises pour survivre a un redemarrage de l'app.
  static const _keyLastTrackId = 'vinland_last_track_id';
  static const _keyLastQueueIds = 'vinland_last_queue_ids';
  static const _keyLastSourceIds = 'vinland_last_source_ids';
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
      _broadcastJamState();
    });
    // Le titre en cours est desormais toujours pousse explicitement par
    // _playSingle() (appele par playTrack/_advance/previousTrack), jamais
    // deduit d'un index rapporte par le moteur audio -- un seul titre a la
    // fois lui est confie (voir _playSingle), donc plus de risque qu'un
    // index de lecteur natif (potentiellement decale par un shuffle natif,
    // cf. l'ancien bug ou la cover/le titre affiches ne correspondaient plus
    // au titre reellement en train de jouer) desynchronise l'affichage.
    _audioHandler.player.currentIndexStream.listen((_) {
      _broadcastJamState();
    });

    // File terminee (dernier titre fini, pas de boucle) : au lieu de couper
    // brutalement, on reboucle sur la meme file (playlist/titres likes/album
    // lances) plutot que de devier vers un autre contenu (cf. le retour des
    // beta testeurs : la lecture "quittait" leur liste pour jouer des titres
    // du meme artiste sans prevenir).
    _audioHandler.player.completedStream.listen((_) {
      _continueQueueAutomatically();
    });
  }

  bool _autoContinuing = false;

  Future<void> _continueQueueAutomatically() async {
    if (_autoContinuing || _isDisposed) return;
    _autoContinuing = true;
    try {
      if (loopMode == LoopMode.one) {
        if (currentTrack != null) await _playSingle(currentTrack!);
        return;
      }
      await _advanceQueue();
    } finally {
      _autoContinuing = false;
    }
  }

  /// Passe au titre suivant de `queue` (la file d'attente). Si elle est
  /// vide, la regenere depuis `_sourceOrder` (le contexte lance -- album,
  /// playlist, titres likes, artiste) au lieu de s'arreter net : c'est le
  /// "reboucler sur la meme file" attendu par les beta-testeurs, qui
  /// s'applique maintenant que la lecture aleatoire soit active ou non
  /// (avant, ce rebouclage rejouait toujours le tout premier titre de la
  /// liste d'origine meme en mode aleatoire -- voir le commentaire sur
  /// `toggleShuffle` pour le detail du bug que ca causait).
  Future<void> _advanceQueue() async {
    if (queue.isEmpty) {
      if (_sourceOrder.isEmpty) return;
      final playedIds = {if (currentTrack != null) currentTrack!.id};
      var refill =
          _sourceOrder.where((t) => !playedIds.contains(t.id)).toList();
      if (refill.isEmpty) refill = List<Track>.of(_sourceOrder);
      if (isShuffled) refill.shuffle();
      queue = refill;
    }
    if (queue.isEmpty) return;
    if (currentTrack != null) _pushHistory(currentTrack!);
    final next = queue.removeAt(0);
    await _playSingle(next);
  }

  /// Un seul notifyListeners() au bout de 50ms, meme s'il y en a 10 d'affilee
  void _notify() {
    // Les etageres "suggestions" de l'accueil ne doivent pas se recalculer a
    // chaque lot recu pendant une synchro (allTracks/albums grossissent
    // alors en continu) -- voir _refreshHomeShelves. Une fois la synchro
    // terminee, _isSyncing repasse a false AVANT ce _notify() final, donc le
    // dernier recalcul avec les donnees completes a bien lieu.
    if (!_isSyncing) _refreshHomeShelves();
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
    _desktopThemeMode = await DesktopTheme.loadMode();
    _desktopThemeColor = await DesktopTheme.loadColor();
    _desktopCoverBlurSigma = await DesktopTheme.loadBlurSigma();
    _mobileThemeMode = await MobileTheme.loadMode();
    _mobileThemeColor = await MobileTheme.loadColor();
    _mobileCoverBlurSigma = await MobileTheme.loadBlurSigma();
    _mobileSolidEffect = await MobileTheme.loadSolidEffect();
    _desktopSolidEffect = await DesktopTheme.loadSolidEffect();
    _mobilePinnedCoverPath = await MobileTheme.loadPinnedCover();
    _desktopPinnedCoverPath = await DesktopTheme.loadPinnedCover();

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

    // Charge les identifiants (I/O local sur le secure storage, pas de
    // reseau) AVANT le premier rendu : sinon hasCredentials/isLoggedIn
    // restent faux le temps de cette lecture et l'ecran de connexion
    // s'affiche brievement avant de basculer sur la home -- flash visible
    // a chaque lancement alors que l'utilisateur est bien "reste connecte".
    await _navidrome.loadStoredCredentials();

    // Rien de plus a attendre pour afficher l'app : "rester connecte" veut
    // dire ne jamais bloquer l'affichage sur un ping reseau. L'authentification
    // live (jusqu'a 10s si le NAS est lent/injoignable) et la resynchro se
    // font en fond.
    _isInitializing = false;
    _notify();

    unawaited(_navidrome.authenticate().then((navidromeOk) {
      if (navidromeOk) {
        // Rafraichit d'abord les URLs des titres deja en cache (pas de reseau,
        // instantane) : sans ca, covers/lecture restent casses le temps que
        // _performSync termine si l'URL de serveur a change depuis le dernier
        // lancement (voir MusicService.refreshNavidromeTrackUrls).
        _music.refreshNavidromeTrackUrls();
        _notify();
        unawaited(_performSync());
      } else {
        _notify();
      }
    }));

    unawaited(checkForUpdate());
  }

  UpdateInfo? updateInfo;

  // Theme du fond desktop (voir desktop/desktop_theme.dart) : solide (couleur
  // RGB choisie par l'utilisateur), cover floutee, ou fenetre transparente
  // (experimental, depend du support de flutter_acrylic sur la machine).
  DesktopThemeMode _desktopThemeMode = DesktopThemeMode.solid;
  DesktopThemeMode get desktopThemeMode => _desktopThemeMode;
  Color _desktopThemeColor = DesktopTheme.defaultColor;
  Color get desktopThemeColor => _desktopThemeColor;

  Future<void> setDesktopThemeMode(DesktopThemeMode mode) async {
    _desktopThemeMode = mode;
    await DesktopTheme.saveMode(mode);
    _notify();
  }

  Future<void> setDesktopThemeColor(Color color) async {
    _desktopThemeColor = color;
    await DesktopTheme.saveColor(color);
    _notify();
  }

  double _desktopCoverBlurSigma = DesktopTheme.defaultBlurSigma;
  double get desktopCoverBlurSigma => _desktopCoverBlurSigma;

  Future<void> setDesktopCoverBlurSigma(double sigma) async {
    _desktopCoverBlurSigma = sigma;
    await DesktopTheme.saveBlurSigma(sigma);
    _notify();
  }

  SolidColorEffect _desktopSolidEffect = SolidColorEffect.flat;
  SolidColorEffect get desktopSolidEffect => _desktopSolidEffect;

  Future<void> setDesktopSolidEffect(SolidColorEffect effect) async {
    _desktopSolidEffect = effect;
    await DesktopTheme.saveSolidEffect(effect);
    _notify();
  }

  String? _desktopPinnedCoverPath;
  String? get desktopPinnedCoverPath => _desktopPinnedCoverPath;

  Future<void> setDesktopPinnedCoverPath(String? path) async {
    _desktopPinnedCoverPath = path;
    await DesktopTheme.savePinnedCover(path);
    _notify();
  }

  // Theme du fond mobile (voir theme/mobile_theme.dart) : equivalent du theme
  // desktop ci-dessus, sans le mode transparent (pas de sens sur une app
  // mobile toujours plein ecran).
  MobileThemeMode _mobileThemeMode = MobileThemeMode.solid;
  MobileThemeMode get mobileThemeMode => _mobileThemeMode;
  Color _mobileThemeColor = MobileTheme.defaultColor;
  Color get mobileThemeColor => _mobileThemeColor;

  Future<void> setMobileThemeMode(MobileThemeMode mode) async {
    _mobileThemeMode = mode;
    await MobileTheme.saveMode(mode);
    _notify();
  }

  Future<void> setMobileThemeColor(Color color) async {
    _mobileThemeColor = color;
    await MobileTheme.saveColor(color);
    _notify();
  }

  double _mobileCoverBlurSigma = MobileTheme.defaultBlurSigma;
  double get mobileCoverBlurSigma => _mobileCoverBlurSigma;

  Future<void> setMobileCoverBlurSigma(double sigma) async {
    _mobileCoverBlurSigma = sigma;
    await MobileTheme.saveBlurSigma(sigma);
    _notify();
  }

  SolidColorEffect _mobileSolidEffect = SolidColorEffect.flat;
  SolidColorEffect get mobileSolidEffect => _mobileSolidEffect;

  Future<void> setMobileSolidEffect(SolidColorEffect effect) async {
    _mobileSolidEffect = effect;
    await MobileTheme.saveSolidEffect(effect);
    _notify();
  }

  String? _mobilePinnedCoverPath;
  String? get mobilePinnedCoverPath => _mobilePinnedCoverPath;

  Future<void> setMobilePinnedCoverPath(String? path) async {
    _mobilePinnedCoverPath = path;
    await MobileTheme.savePinnedCover(path);
    _notify();
  }

  // Photo de profil (voir services/avatar_service.dart) : incrementee a
  // chaque upload reussi pour invalider le cache d'image (meme URL, fichier
  // remplace cote serveur -- voir UserAvatar.cacheBust).
  int _avatarVersion = 0;
  int get avatarVersion => _avatarVersion;

  Future<bool> uploadMyAvatar(File file) async {
    final username = userName;
    if (username == null) return false;
    final ok =
        await AvatarService().uploadAvatar(username: username, file: file);
    if (ok) {
      _avatarVersion++;
      _notify();
    }
    return ok;
  }

  // Visible feedback de la synchro Navidrome : sans ca, un premier lancement
  // (cache local vide) sur un reseau lent/injoignable affiche une app
  // silencieusement vide, indiscernable d'un vrai bug pour l'utilisateur
  // (voir le compte-rendu d'un ami testeur : "aucune musique, aucune
  // recommandation" alors que la vraie cause etait une synchro qui n'avait
  // pas fini, ou avait echoue, sans aucun signal a l'ecran).
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  /// Vrai seulement apres une synchro terminee (pas au tout premier
  /// chargement) qui n'a ramene aucun titre -- signal qu'il y a probablement
  /// un souci de connexion au serveur plutot qu'une bibliotheque vide.
  bool _lastSyncEmpty = false;
  bool get lastSyncEmpty => _lastSyncEmpty;

  Future<void> _performSync() async {
    _isSyncing = true;
    _notify();
    try {
      // onProgress : la bibliotheque (allTracks/albums) se remplit lot par
      // lot pendant la synchro -- _notify() est deja debounce (50ms), donc
      // ca ne fait pas plus de rebuilds qu'une barre de progression normale.
      await _music.syncWithNavidrome(onProgress: _notify);
      _lastSyncEmpty = _music.navidromeTracks.isEmpty;
    } finally {
      _useNavidrome = _music.navidromeTracks.isNotEmpty;
      _isSyncing = false;
      _notify();
    }
  }

  Future<void> checkForUpdate() async {
    updateInfo = await UpdateCheckService().checkForUpdate();
    if (updateInfo != null) _notify();
  }

  /// Recharge le dernier titre joue (pour l'affichage dans le mini-player,
  /// sans relancer la lecture automatiquement) ainsi que les modes lecture
  /// aleatoire/repetition, a partir du cache local deja charge par
  /// `_music.initialize()` (pas besoin d'attendre la sync Navidrome).
  Future<void> _restorePlaybackState(SharedPreferences prefs) async {
    isShuffled = prefs.getBool(_keyShuffleEnabled) ?? false;
    final loopName = prefs.getString(_keyLoopMode);
    if (loopName != null) {
      loopMode = LoopMode.values
          .firstWhere((m) => m.name == loopName, orElse: () => LoopMode.off);
    }

    final lastTrackId = prefs.getString(_keyLastTrackId);
    if (lastTrackId == null) return;
    final track = _findTrackById(lastTrackId);
    if (track == null) return;

    final queueIds = prefs.getStringList(_keyLastQueueIds) ?? [];
    queue = queueIds.map(_findTrackById).whereType<Track>().toList();
    final sourceIds =
        prefs.getStringList(_keyLastSourceIds) ?? [lastTrackId, ...queueIds];
    _sourceOrder = sourceIds.map(_findTrackById).whereType<Track>().toList();
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
    await prefs.setStringList(
        _keyLastSourceIds, _sourceOrder.map((t) => t.id).toList());
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
    await prefs.remove(_keyLastSourceIds);
    await prefs.remove(_keyLastQueueIndex);
    await prefs.remove(_keyShuffleEnabled);
    await prefs.remove(_keyLoopMode);
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _notifyDebounce?.cancel();
    _jamHeartbeat?.cancel();
    _jamStateSub?.cancel();
    _jamHostLeftSub?.cancel();
    _jamCountSub?.cancel();
    unawaited(_jam.leave());
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
    _sourceOrder = [];
    _history.clear();
    await _clearPlaybackState();
    _notify();
  }

  /// Lance `track` et construit la file d'attente a partir de `trackList`
  /// (le contexte -- album, playlist, titres likes, artiste...) : tout ce
  /// qui suit `track` dans cette liste devient `queue` (melange une fois si
  /// la lecture aleatoire est active). `trackList` devient aussi
  /// `_sourceOrder`, reutilise pour regenerer la file quand elle s'epuise ou
  /// qu'on (re)bascule le mode aleatoire.
  Future<void> playTrack(Track track, {List<Track>? trackList}) async {
    // Participant d'une session Jam (pas hote) : suit passivement l'etat
    // recu du relais (voir _applyJamState), ne pilote jamais la lecture
    // lui-meme -- sauf l'appel interne fait par _applyJamState, qui doit
    // pouvoir passer.
    if (isJamActive && !isJamHost && !_applyingJamState) return;
    _history.clear();
    _sourceOrder = trackList ?? [track];
    final startIndex = _sourceOrder.indexWhere((t) => t.id == track.id);
    var remainder = startIndex == -1
        ? <Track>[]
        : _sourceOrder.sublist(startIndex + 1);
    if (isShuffled) remainder = List<Track>.of(remainder)..shuffle();
    queue = remainder;
    await _playSingle(track);
  }

  /// Charge et joue un seul titre dans le moteur audio, sans toucher a
  /// `queue`/`_sourceOrder`/`_history` : c'est le point commun a playTrack,
  /// _advanceQueue, previousTrack et togglePlayPause (reprise apres
  /// redemarrage de l'app). Un seul titre a la fois est confie au moteur --
  /// voir le commentaire sur le champ `queue` pour le bug (natif shuffle
  /// desynchronisant l'affichage) que ca evite.
  Future<void> _playSingle(Track track) async {
    currentTrack = track;
    final path = _music.getOfflinePath(track.id) ?? track.filePath!;
    final isAsset = path.startsWith('assets/');
    final isRemote = path.startsWith('http');

    Uri? artUri;
    if (track.coverPath != null) {
      artUri = track.coverPath!.startsWith('http')
          ? Uri.parse(track.coverPath!)
          : Uri.file(track.coverPath!);
    }

    final item = MediaItem(
      id: path,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
      artUri: artUri,
      extras: {'isAsset': isAsset, 'isRemote': isRemote},
    );

    _updateDominantColor(track.coverPath);
    _notify();
    await Future.delayed(Duration.zero);
    await _audioHandler.loadAndPlay([item], 0);
    isPlaying = true;
    await _music.recordPlay(track.id);
    _music.updateNowPlaying(track.id,
        jamSessionId: isJamHost ? jamSessionId : null);
    // Voir NavidromeService.scrobble : fait remonter la lecture au NAS pour
    // que la regle de suppression des morceaux peu ecoutes puisse s'appuyer
    // dessus. Ids locaux/hors-Navidrome (assets, imports) n'ont pas
    // d'equivalent cote serveur, on ne les envoie pas.
    if (track.id.startsWith('navidrome_')) {
      unawaited(_navidrome.scrobble(track.id));
    }
    unawaited(_savePlaybackState());
    _notify();
  }

  void togglePlayPause() {
    if (isJamActive && !isJamHost && !_applyingJamState) return;
    // Redemarrage de l'app : le mini-player affiche le dernier titre joue
    // mais aucune source audio n'a encore ete chargee dans le player. Un
    // simple play()/pause() sur un player vide ne fait rien : il faut
    // relancer une vraie lecture -- sans toucher a la file restauree.
    if (currentTrack != null && !_audioHandler.player.hasSource) {
      _playSingle(currentTrack!);
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

  Future<void> nextTrack() async {
    if (isJamActive && !isJamHost) return;
    await _advanceQueue();
  }

  /// Avant 3s de lecture : revient au titre precedent (file d'attente
  /// remise en tete). Au-dela : redemarre simplement le titre en cours,
  /// comme la plupart des lecteurs.
  Future<void> previousTrack() async {
    if (isJamActive && !isJamHost) return;
    if (position > const Duration(seconds: 3) || _history.isEmpty) {
      seek(Duration.zero);
      return;
    }
    if (currentTrack != null) queue.insert(0, currentTrack!);
    final prev = _history.removeLast();
    await _playSingle(prev);
  }

  /// Saute directement au titre en position `index` de la file d'attente :
  /// tout ce qui le precedait dans `queue` est abandonne (jamais joue, donc
  /// pas ajoute a l'historique).
  Future<void> playFromQueue(int index) async {
    if (index < 0 || index >= queue.length) return;
    if (currentTrack != null) _pushHistory(currentTrack!);
    queue.removeRange(0, index);
    final target = queue.removeAt(0);
    await _playSingle(target);
  }

  /// "Ajouter a la file d'attente" (options d'un titre) : le place a la fin
  /// de `queue`.
  void addToQueue(Track track) {
    queue.add(track);
    unawaited(_savePlaybackState());
    _notify();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= queue.length) return;
    queue.removeAt(index);
    unawaited(_savePlaybackState());
    _notify();
  }

  /// Reordonnancement par glisser-deposer (voir QueueScreen) : `newIndex`
  /// suit la convention de ReorderableListView.onReorder (index cible avant
  /// le retrait de l'element deplace).
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);
    unawaited(_savePlaybackState());
    _notify();
  }

  void seek(Duration pos) {
    if (isJamActive && !isJamHost && !_applyingJamState) return;
    _audioHandler.seek(pos);
    _notify();
  }

  /// Demarre une session Jam en tant qu'hote : pilote la lecture normalement,
  /// diffuse son etat (titre/position/lecture-pause) aux participants via le
  /// relais (voir jam_relay/) a chaque changement et toutes les 5s pour
  /// rattraper la derive. Renvoie le sessionId a partager, ou null en cas
  /// d'echec (relais injoignable).
  Future<String?> startJamSession() async {
    final id = _jam.generateSessionId();
    final ok = await _jam.host(id);
    if (!ok) return null;
    _jamCountSub?.cancel();
    _jamCountSub = _jam.participantCountStream.listen((count) {
      jamParticipantCount = count;
      _notify();
    });
    _jamHeartbeat?.cancel();
    _jamHeartbeat =
        Timer.periodic(const Duration(seconds: 5), (_) => _broadcastJamState());
    _broadcastJamState();
    if (currentTrack != null) {
      _music.updateNowPlaying(currentTrack!.id, jamSessionId: id);
    }
    _notify();
    return id;
  }

  /// Rejoint une session Jam existante : suit passivement l'etat de l'hote
  /// (voir _applyJamState), les actions de lecture locales sont ignorees
  /// tant que la session est active (cf. playTrack/togglePlayPause/etc.).
  Future<bool> joinJamSession(String sessionId) async {
    final ok = await _jam.join(sessionId);
    if (!ok) return false;
    _jamStateSub?.cancel();
    _jamStateSub = _jam.stateStream.listen(_applyJamState);
    _jamHostLeftSub?.cancel();
    _jamHostLeftSub = _jam.hostLeftStream.listen((_) {
      leaveJamSession();
    });
    _notify();
    return true;
  }

  Future<void> leaveJamSession() async {
    final wasHost = isJamHost;
    _jamHeartbeat?.cancel();
    _jamHeartbeat = null;
    await _jamStateSub?.cancel();
    _jamStateSub = null;
    await _jamHostLeftSub?.cancel();
    _jamHostLeftSub = null;
    await _jamCountSub?.cancel();
    _jamCountSub = null;
    await _jam.leave();
    jamParticipantCount = 0;
    if (wasHost && currentTrack != null) {
      _music.updateNowPlaying(currentTrack!.id);
    }
    _notify();
  }

  void _broadcastJamState() {
    if (!_jam.isActive || !_jam.isHost) return;
    final track = currentTrack;
    if (track == null) return;
    _jam.sendState(
      trackId: track.id,
      positionMs: position.inMilliseconds,
      isPlaying: isPlaying,
    );
  }

  /// Applique l'etat recu de l'hote (voir joinJamSession) : change de titre
  /// si besoin, rattrape la position (compensee du delai de transit reseau
  /// via le timestamp d'envoi), aligne play/pause. _applyingJamState laisse
  /// passer ces appels a travers les gardes de playTrack/seek/etc. qui
  /// bloquent sinon toute action de lecture locale pendant une session suivie.
  Future<void> _applyJamState(JamStateMessage msg) async {
    _applyingJamState = true;
    try {
      if (currentTrack?.id != msg.trackId) {
        final track = _findTrackById(msg.trackId);
        if (track != null) {
          await playTrack(track, trackList: [track]);
        }
      }
      final latencyMs =
          (DateTime.now().millisecondsSinceEpoch - msg.ts).clamp(0, 5000);
      await _audioHandler.player
          .seek(Duration(milliseconds: msg.positionMs + latencyMs));
      if (msg.isPlaying && !isPlaying) {
        await _audioHandler.play();
      } else if (!msg.isPlaying && isPlaying) {
        await _audioHandler.pause();
      }
    } finally {
      _applyingJamState = false;
    }
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

  Future<void> toggleSuperLike(String trackId) async {
    await _music.toggleSuperLike(trackId);
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

  Future<String?> createCollabPlaylist(String name) async {
    final groupId = await _music.createCollabPlaylist(name);
    _notify();
    return groupId;
  }

  Future<bool> joinCollabPlaylist(String groupId, String name) async {
    final ok = await _music.joinCollabPlaylist(groupId, name);
    _notify();
    return ok;
  }

  Future<CollabPlaylistView> fetchCollabPlaylist(String groupId) =>
      _music.fetchCollabPlaylist(groupId);

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

  /// Ajoute des titres manquants sans ecraser ceux d'un import CSV
  /// precedent (contrairement a [setMissingTracks]) -- ils ne sont retires
  /// que via [clearMissingTracks] (bouton "Effacer" de l'ecran dedie), donc
  /// un nouvel import ne doit pas faire disparaitre les fantomes d'un import
  /// anterieur de la liste "Titres likes".
  void addMissingTracks(List<Map<String, dynamic>> tracks) {
    _music.addMissingTracks(tracks);
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

  bool get shareRecentPlaysWithFriends => _music.shareRecentPlaysWithFriends;

  Future<void> setShareRecentPlaysWithFriends(bool value) async {
    await _music.setShareRecentPlaysWithFriends(value);
    _notify();
  }

  bool get shareNowPlayingWithFriends => _music.shareNowPlayingWithFriends;

  Future<void> setShareNowPlayingWithFriends(bool value) async {
    await _music.setShareNowPlayingWithFriends(value);
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
  List<RecentPlay> get recentPlays => _music.recentPlays.take(8).toList();

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
      if (ok) await _performSync();
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
      // une fois que l'utilisateur est deja entre dans l'app. isSyncing
      // reste visible a l'ecran pendant ce temps (voir _performSync).
      unawaited(_performSync());
    }
    _notify();
    return ok;
  }

  Future<void> syncNavidrome() async {
    await _performSync();
  }

  /// Rafraichissement rapide (quelques albums recents, pas toute la
  /// bibliotheque) apres un telechargement automatique -- voir
  /// MusicService.syncRecentlyAdded. Ne passe pas par _isSyncing/_performSync :
  /// contrairement a une synchro complete, celui-ci ne rend rien injouable
  /// pendant son execution, donc pas besoin du signal "synchro en cours".
  Future<void> syncRecentlyAdded() async {
    await _music.syncRecentlyAdded();
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

  /// Bascule le mode aleatoire : regenere la partie "contexte" de la file
  /// (ce qui reste de _sourceOrder a jouer) dans le bon ordre -- melange si
  /// on l'active, ordre d'origine si on le desactive -- tout en preservant
  /// les titres ajoutes manuellement via "Ajouter a la file d'attente" qui
  /// ne font pas partie de ce contexte (ils restent en tete, inchanges).
  Future<void> toggleShuffle() async {
    isShuffled = !isShuffled;
    final playedIds = {
      ..._history.map((t) => t.id),
      if (currentTrack != null) currentTrack!.id,
    };
    var contextRemainder =
        _sourceOrder.where((t) => !playedIds.contains(t.id)).toList();
    if (isShuffled) contextRemainder.shuffle();
    final manuallyQueued =
        queue.where((t) => !_sourceOrder.any((s) => s.id == t.id)).toList();
    queue = [...manuallyQueued, ...contextRemainder];
    unawaited(_saveShuffleLoopState());
    _notify();
  }

  Future<void> toggleLoopMode() async {
    loopMode = {
      LoopMode.off: LoopMode.all,
      LoopMode.all: LoopMode.one,
      LoopMode.one: LoopMode.off,
    }[loopMode]!;
    unawaited(_saveShuffleLoopState());
    _notify();
  }

  Future<void> clearAllLikes() async {
    await _music.clearAllLikes();
    _notify();
  }
}
