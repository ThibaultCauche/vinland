import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:audio_service/audio_service.dart';
import 'package:palette_generator/palette_generator.dart';
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
import '../services/bluetooth_trusted_devices_service.dart';
import '../services/avatar_service.dart';
import '../services/download_worker_service.dart';
import '../services/matching_service.dart';
import '../services/share_inbox_service.dart';
import '../screens/album_screen.dart';
import '../screens/playlist_screen.dart';
import '../widgets/player_screen.dart';
import '../desktop/desktop_theme.dart';
import '../theme/mobile_theme.dart';
import '../theme/solid_color_effect.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
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
  StreamSubscription? _jamCommandSub;
  Timer? _jamHeartbeat;
  Timer? _personalSyncPoll;
  bool _applyingJamState = false;

  // Synchro multi-appareils "perso" (voir _maybeBecomePersonalHost /
  // _tryJoinPersonalSync) : reutilise le relais Jam mais avec une session
  // deterministe par compte (pas de code a partager) et, cote participant,
  // affichage + controle a distance seulement -- l'audio n'est jamais joue
  // en double, contrairement au Jam "entre amis" classique.
  bool _personalSyncMode = false;
  Track? remoteTrack;
  bool remoteIsPlaying = false;
  String? remoteDeviceName;
  bool get isPersonalSyncParticipant =>
      _personalSyncMode && isJamActive && !isJamHost;

  String get _deviceLabel {
    if (Platform.isAndroid) return 'Telephone';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isWindows) return 'PC';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isLinux) return 'Linux';
    return 'Appareil';
  }

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
  //
  // Pendant une synchro (_performSync), les titres arrivent lot par lot et
  // _music.likedTracks change donc de contenu/ordre a chaque _notify() --
  // visible et genant sur la page "Titres likes". On fige plutot un instantane
  // pris juste avant le debut de la synchro (_frozenLikedTracks) et on ne
  // bascule sur la version fraiche qu'une fois la synchro terminee.
  List<Track>? _frozenLikedTracks;
  List<Track> get likedTracks => _frozenLikedTracks ?? _music.likedTracks;

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

    final combined = [...likedTracks, ...placeholders];
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
  // Contrairement a isLoggedIn (identifiants presents en local, pas de
  // reseau), reflete la vraie authentification live aupres du serveur --
  // necessaire par ex. pour un lien vinland:// ouvert au demarrage a froid,
  // qui doit attendre plus que le simple flag "identifiants charges" avant
  // de chercher l'element vise (voir DeepLinkService._waitUntilReady).
  bool get isNavidromeConnected => _navidrome.isConnected;
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

  // Frequence de la synchro complete (voir _performSync) : une resynchro
  // integrale de toute la bibliotheque a chaque ouverture est lente sur une
  // grosse bibliotheque et risque de tomber pendant un import CSV/un like en
  // cours (voir MusicService.lightSync). Entre deux, une synchro "legere"
  // (juste les likes serveur + derniers albums) suffit a garder l'app a jour.
  static const _keyLastFullSyncAt = 'vinland_last_full_sync_at';
  static const _fullSyncInterval = Duration(hours: 6);
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
      _checkStall(pos);
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

  // Filet de securite : sur certains appareils Android, en arriere-plan
  // (ecran eteint, telephone en poche en exterieur), le processingState
  // just_audio n'atteint parfois jamais `completed` en fin de titre -- rien
  // ne declenche alors _continueQueueAutomatically et la lecture reste
  // bloquee, position figee en fin de titre, jusqu'a ce qu'on relance a la
  // main (retour testeur). Des qu'on approche de la fin, on arme un minuteur
  // qui force le passage au titre suivant si rien n'a bouge 2s plus tard --
  // annule/reutilise en boucle sinon, donc sans effet en fonctionnement
  // normal (completedStream a largement le temps de faire avancer la file
  // avant que ce filet ne se declenche).
  Timer? _stallWatchdog;

  void _checkStall(Duration pos) {
    // Comme dans _SeekBar (desktop) : la duree rapportee par le moteur
    // audio peut etre fausse/trop courte en debut de lecture d'un flux
    // Navidrome sans Content-Length (elle "grimpe" par paliers) -- s'y fier
    // ici declenchait ce filet bien avant la vraie fin et redemarrait le
    // titre depuis 0 (retour testeur). La duree des metadonnees du titre
    // est fiable des le debut, on la prefere. pos > 3s ecarte en plus toute
    // lecture a peine demarree d'un declenchement immediat.
    final track = currentTrack;
    final dur = (track != null && track.duration.inMilliseconds > 0)
        ? track.duration
        : duration;
    final nearEnd = isPlaying &&
        dur.inMilliseconds > 0 &&
        pos.inMilliseconds > 3000 &&
        (dur - pos).inMilliseconds < 800;
    if (!nearEnd) {
      _stallWatchdog?.cancel();
      _stallWatchdog = null;
      return;
    }
    if (_stallWatchdog != null) return; // deja arme pour ce titre
    final stalledTrackId = currentTrack?.id;
    _stallWatchdog = Timer(const Duration(seconds: 2), () {
      _stallWatchdog = null;
      // Toujours sur le meme titre malgre les 2s ecoulees : la transition
      // normale n'a pas eu lieu, on la force nous-memes.
      if (isPlaying && currentTrack?.id == stalledTrackId) {
        _continueQueueAutomatically();
      }
    });
  }

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
  /// Nombre de titres consecutifs qu'on a du sauter faute d'avoir reussi a
  /// les charger (voir _advanceQueue) -- protege contre une boucle infinie
  /// si le reseau est completement coupe (sinon chaque titre de la file
  /// echouerait et relancerait immediatement le suivant, sans jamais
  /// s'arreter).
  int _consecutiveLoadFailures = 0;
  static const _maxConsecutiveLoadFailures = 3;

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
    final loaded = await _playSingle(next);
    if (!loaded) {
      // Titre injouable (reseau/fichier) : plutot que de rester bloque en
      // silence dessus (le bug remonte par un testeur en exterieur), on
      // passe au suivant -- sauf si plusieurs echecs de suite suggerent que
      // le reseau est totalement coupe, auquel cas on abandonne pour de bon
      // au lieu de vider toute la file d'attente en boucle.
      _consecutiveLoadFailures++;
      if (_consecutiveLoadFailures < _maxConsecutiveLoadFailures) {
        await _advanceQueue();
      }
      return;
    }
    _consecutiveLoadFailures = 0;
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

  /// Le shell desktop (DesktopAppShell) a sa propre pile de navigation
  /// locale, separee de pushOverlay/currentOverlay ci-dessous (pensee pour
  /// des ecrans mobiles pleine page) -- voir le commentaire sur
  /// DesktopAppShell. Il s'enregistre ici a son montage pour que du code qui
  /// n'a pas acces a son State (ex: DeepLinkService, qui ouvre un
  /// album/playlist partage) puisse l'atteindre quelle que soit la
  /// plateforme.
  void Function(Album album)? onDesktopOpenAlbum;
  void Function(Playlist playlist)? onDesktopOpenPlaylist;

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

    if (!kIsWeb && Platform.isAndroid) {
      BluetoothTrustedDevicesService().onTrustedDeviceConnected(() {
        if (!isPlaying) togglePlayPause();
      });
    }

    // Charge les identifiants (I/O local sur le secure storage, pas de
    // reseau) AVANT le premier rendu : sinon hasCredentials/isLoggedIn
    // restent faux le temps de cette lecture et l'ecran de connexion
    // s'affiche brievement avant de basculer sur la home -- flash visible
    // a chaque lancement alors que l'utilisateur est bien "reste connecte".
    await _navidrome.loadStoredCredentials();
    _startPersonalSyncPolling();

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
        unawaited(loadPendingShares());
      } else {
        _notify();
      }
    }));

    unawaited(checkForUpdate());
    WidgetsBinding.instance.addObserver(this);
  }

  /// Sans ca, une app relancee depuis l'arriere-plan (le cas courant sur
  /// mobile -- l'OS ne "ferme" quasiment jamais une app, il la met juste en
  /// pause) ne revoit jamais le check fait au vrai cold start dans
  /// initialize(), et une mise a jour fraichement publiee reste invisible
  /// tant que l'utilisateur ne va pas cliquer "Verifier les mises a jour"
  /// dans Parametres.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(checkForUpdate());
      unawaited(loadPendingShares());
    }
  }

  UpdateInfo? updateInfo;

  // Sur Android, le prompt de mise a jour ne doit s'afficher qu'une fois par
  // session (voir _MobileAppShell dans main.dart) -- sans ca il reapparaitrait
  // a chaque rebuild de l'ecran d'accueil tant que la mise a jour n'est pas
  // installee.
  bool updatePromptShown = false;

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
    final prefs = await SharedPreferences.getInstance();
    final lastFullMs = prefs.getInt(_keyLastFullSyncAt);
    final lastFull =
        lastFullMs != null ? DateTime.fromMillisecondsSinceEpoch(lastFullMs) : null;
    final needsFullSync = _music.navidromeTracks.isEmpty ||
        lastFull == null ||
        DateTime.now().difference(lastFull) > _fullSyncInterval;
    debugPrint('PERFORM SYNC: needsFullSync=$needsFullSync '
        '(tracksEnCache=${_music.navidromeTracks.length}, lastFullSync=$lastFull)');

    _isSyncing = true;
    _frozenLikedTracks = List.of(_music.likedTracks);
    _notify();
    try {
      if (needsFullSync) {
        // onProgress : la bibliotheque (allTracks/albums) se remplit lot par
        // lot pendant la synchro -- _notify() est deja debounce (50ms), donc
        // ca ne fait pas plus de rebuilds qu'une barre de progression normale.
        // likedTracks reste fige (_frozenLikedTracks) tant que ca tourne.
        await _music.syncWithNavidrome(onProgress: _notify);
        await prefs.setInt(
            _keyLastFullSyncAt, DateTime.now().millisecondsSinceEpoch);
      } else {
        await _music.lightSync();
      }
      _lastSyncEmpty = _music.navidromeTracks.isEmpty;
    } finally {
      _useNavidrome = _music.navidromeTracks.isNotEmpty;
      _isSyncing = false;
      _frozenLikedTracks = null;
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
    WidgetsBinding.instance.removeObserver(this);
    _notifyDebounce?.cancel();
    _stallWatchdog?.cancel();
    _jamHeartbeat?.cancel();
    _personalSyncPoll?.cancel();
    _jamStateSub?.cancel();
    _jamHostLeftSub?.cancel();
    _jamCountSub?.cancel();
    _jamCommandSub?.cancel();
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
      debugPrint('logout: audioHandler.stop() a echoue/timeout: $e');
    }
    // Sans ca, une session Jam active survivait a la deconnexion : le compte
    // qui se reconnecte ensuite (ou un simple changement de compte, meme
    // mecanisme) heritait d'une session WebSocket ouverte sous une identite
    // qui n'est plus la sienne (voir dispose(), qui fait deja ce nettoyage a
    // la fermeture complete de l'app -- logout() doit faire pareil).
    unawaited(_jam.leave());
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
    if (isJamActive && !isJamHost && !_applyingJamState && !_personalSyncMode) {
      return;
    }
    _history.clear();
    _sourceOrder = trackList ?? [track];
    final startIndex = _sourceOrder.indexWhere((t) => t.id == track.id);
    var remainder = startIndex == -1
        ? <Track>[]
        : _sourceOrder.sublist(startIndex + 1);
    if (isShuffled) remainder = List<Track>.of(remainder)..shuffle();
    queue = remainder;
    _consecutiveLoadFailures = 0;
    await _playSingle(track);
  }

  /// Charge et joue un seul titre dans le moteur audio, sans toucher a
  /// `queue`/`_sourceOrder`/`_history` : c'est le point commun a playTrack,
  /// _advanceQueue, previousTrack et togglePlayPause (reprise apres
  /// redemarrage de l'app). Un seul titre a la fois est confie au moteur --
  /// voir le commentaire sur le champ `queue` pour le bug (natif shuffle
  /// desynchronisant l'affichage) que ca evite. Retourne false si le moteur
  /// n'a pas reussi a charger le titre (voir _advanceQueue, qui saute au
  /// suivant plutot que de laisser la lecture bloquee en silence).
  Future<bool> _playSingle(Track track) async {
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
    final loaded = await _audioHandler.loadAndPlay([item], 0);
    isPlaying = loaded;
    if (!loaded) {
      _notify();
      return false;
    }
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
    // Prend/garde le role d'hote de la synchro perso multi-appareils (voir
    // _maybeBecomePersonalHost) tant qu'aucune session Jam entre amis
    // manuelle n'est en cours -- diffuse aussi l'etat si deja hote.
    unawaited(_maybeBecomePersonalHost());
    _notify();
    return true;
  }

  void togglePlayPause() {
    if (isJamActive && !isJamHost && !_applyingJamState && !_personalSyncMode) {
      return;
    }
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
    if (isJamHost) _broadcastJamState();
    _notify();
  }

  Future<void> nextTrack() async {
    if (isJamActive && !isJamHost && !_personalSyncMode) return;
    await _advanceQueue();
  }

  /// Avant 3s de lecture : revient au titre precedent (file d'attente
  /// remise en tete). Au-dela : redemarre simplement le titre en cours,
  /// comme la plupart des lecteurs.
  Future<void> previousTrack() async {
    if (isJamActive && !isJamHost && !_personalSyncMode) return;
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
    if (isJamActive && !isJamHost && !_applyingJamState && !_personalSyncMode) {
      return;
    }
    _audioHandler.seek(pos);
    _notify();
  }

  /// Demarre une session Jam en tant qu'hote : pilote la lecture normalement,
  /// diffuse son etat (titre/position/lecture-pause) aux participants via le
  /// relais (voir jam_relay/) a chaque changement et toutes les 5s pour
  /// rattraper la derive. Renvoie le sessionId a partager, ou null en cas
  /// d'echec (relais injoignable).
  Future<String?> startJamSession() async {
    _personalSyncMode = false;
    remoteTrack = null;
    remoteIsPlaying = false;
    remoteDeviceName = null;
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
    _personalSyncMode = false;
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
    _personalSyncMode = false;
    _jamHeartbeat?.cancel();
    _jamHeartbeat = null;
    await _jamStateSub?.cancel();
    _jamStateSub = null;
    await _jamHostLeftSub?.cancel();
    _jamHostLeftSub = null;
    await _jamCountSub?.cancel();
    _jamCountSub = null;
    await _jamCommandSub?.cancel();
    _jamCommandSub = null;
    await _jam.leave();
    jamParticipantCount = 0;
    if (wasHost && currentTrack != null) {
      _music.updateNowPlaying(currentTrack!.id);
    }
    _notify();
  }

  /// Vrai seulement pour une session Jam "entre amis" demarree/rejointe
  /// manuellement (menu Jam) -- exclut la synchro perso multi-appareils
  /// (silencieuse, jamais affichee dans ce menu). Utilise par
  /// jam_controls.dart et l'icone Jam de la barre de lecture desktop.
  bool get isFriendJamActive => isJamActive && !_personalSyncMode;

  void _broadcastJamState() {
    if (!_jam.isActive || !_jam.isHost) return;
    final track = currentTrack;
    if (track == null) return;
    _jam.sendState(
      trackId: track.id,
      positionMs: position.inMilliseconds,
      isPlaying: isPlaying,
      deviceName: _deviceLabel,
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

  /// Sondage periodique (voir initialize()) : tant qu'aucune session Jam
  /// n'est active, tente de rejoindre la synchro perso de ce compte -- si un
  /// autre appareil est deja hote, on le retrouve automatiquement sans
  /// action utilisateur, meme si cet appareil-ci n'etait pas ouvert quand
  /// l'autre a demarre sa lecture.
  // ponytail: sondage simple (toutes les 20s) plutot qu'un mecanisme de
  // presence -- suffisant a l'echelle d'un usage personnel multi-appareils,
  // a revoir si ca devient sensible a la latence/batterie.
  void _startPersonalSyncPolling() {
    _personalSyncPoll?.cancel();
    _personalSyncPoll =
        Timer.periodic(const Duration(seconds: 20), (_) => _tryJoinPersonalSync());
    _tryJoinPersonalSync();
  }

  Future<void> _tryJoinPersonalSync() async {
    if (isJamActive) return;
    final username = _navidrome.username;
    if (username == null) return;
    final id = _jam.personalSessionId(username);
    final ok = await _jam.join(id);
    if (!ok) return;
    _personalSyncMode = true;
    _jamStateSub?.cancel();
    _jamStateSub = _jam.stateStream.listen(_applyPersonalSyncState);
    _jamHostLeftSub?.cancel();
    _jamHostLeftSub = _jam.hostLeftStream.listen((_) => _leavePersonalSync());
    _notify();
  }

  /// Affiche seulement l'etat recu d'un autre appareil du meme compte --
  /// contrairement a _applyJamState (Jam entre amis), ne joue jamais l'audio
  /// localement : voir remoteTrack/remoteIsPlaying/remoteDeviceName et les
  /// boutons de la barre de lecture qui pilotent l'hote via remoteToggle/
  /// remoteNext/remotePrevious plutot que le moteur audio local.
  void _applyPersonalSyncState(JamStateMessage msg) {
    remoteTrack = _findTrackById(msg.trackId);
    remoteIsPlaying = msg.isPlaying;
    remoteDeviceName = msg.deviceName;
    _notify();
  }

  Future<void> _leavePersonalSync() async {
    _personalSyncMode = false;
    remoteTrack = null;
    remoteIsPlaying = false;
    remoteDeviceName = null;
    await _jamStateSub?.cancel();
    _jamStateSub = null;
    await _jamHostLeftSub?.cancel();
    _jamHostLeftSub = null;
    await _jam.leave();
    _notify();
  }

  /// Prend (ou garde) le role d'hote de la synchro perso a chaque lecture
  /// locale reelle (voir _playSingle) -- jamais pendant une session Jam
  /// entre amis manuelle. C'est ce qui fait qu'appuyer sur play sur
  /// n'importe quel appareil du compte le rend autoritaire, exactement comme
  /// changer d'appareil actif dans Spotify Connect.
  Future<void> _maybeBecomePersonalHost() async {
    if (isJamActive && !_personalSyncMode) return;
    if (isJamActive && isJamHost) {
      _broadcastJamState();
      return;
    }
    final username = _navidrome.username;
    if (username == null) return;
    await _jamStateSub?.cancel();
    _jamStateSub = null;
    await _jamHostLeftSub?.cancel();
    _jamHostLeftSub = null;
    remoteTrack = null;
    remoteIsPlaying = false;
    remoteDeviceName = null;

    final id = _jam.personalSessionId(username);
    final ok = await _jam.host(id);
    if (!ok) return;
    _personalSyncMode = true;
    _jamCommandSub?.cancel();
    _jamCommandSub = _jam.commandStream.listen(_applyJamCommand);
    _jamHeartbeat?.cancel();
    _jamHeartbeat =
        Timer.periodic(const Duration(seconds: 5), (_) => _broadcastJamState());
    _broadcastJamState();
    _notify();
  }

  void _applyJamCommand(JamCommandMessage cmd) {
    switch (cmd.action) {
      case 'toggle':
        togglePlayPause();
        break;
      case 'next':
        nextTrack();
        break;
      case 'previous':
        previousTrack();
        break;
    }
  }

  /// Controles de la barre de lecture cote appareil "spectateur" (voir
  /// isPersonalSyncParticipant) : n'agissent jamais sur le moteur audio
  /// local, envoient une commande a l'appareil hote via le relais.
  void remoteToggle() {
    if (!isPersonalSyncParticipant) return;
    _jam.sendCommand('toggle');
  }

  void remoteNext() {
    if (!isPersonalSyncParticipant) return;
    _jam.sendCommand('next');
  }

  void remotePrevious() {
    if (!isPersonalSyncParticipant) return;
    _jam.sendCommand('previous');
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

  Future<String> createPlaylist(String name) async {
    final id = await _music.createPlaylist(name);
    _notify();
    return id;
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

  Future<void> removeFromPlaylist(String playlistId, String trackId) async {
    await _music.removeFromPlaylist(playlistId, trackId);
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

  /// Voir MusicService.resolveMissingTrack.
  Future<void> resolveMissingTrack(
      Map<String, dynamic> entry, String trackId) async {
    await _music.resolveMissingTrack(entry, trackId);
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

  // BOITE DE RECEPTION DE PARTAGES (phase 2 du partage titre/album/playlist,
  // voir deep_link_service.dart pour la phase 1 -- lien envoye via le
  // partage natif OS) : permet d'envoyer un partage CIBLE a un ami precis,
  // via le petit service maison share-inbox/ (voir ShareInboxService).
  final ShareInboxService _shareInbox = ShareInboxService();
  List<ReceivedShare> pendingShares = [];
  bool get shareInboxConfigured => _shareInbox.isConfigured;

  Future<void> loadPendingShares() async {
    final me = userName;
    if (me == null || !_shareInbox.isConfigured) return;
    pendingShares = await _shareInbox.fetchShares(me);
    _notify();
  }

  Future<bool> sendShareToFriend({
    required String toUsername,
    required String type,
    required String itemId,
    required String title,
    required String subtitle,
  }) async {
    final me = userName;
    if (me == null) return false;
    return _shareInbox.sendShare(
      to: toUsername,
      from: me,
      type: type,
      itemId: itemId,
      title: title,
      subtitle: subtitle,
    );
  }

  /// Retire [share] de la liste affichee immediatement (l'utilisateur vient
  /// de l'ouvrir ou de l'ignorer), puis le supprime cote serveur en best-effort.
  Future<void> dismissShare(ReceivedShare share) async {
    pendingShares = pendingShares.where((s) => s.id != share.id).toList();
    _notify();
    final me = userName;
    if (me != null) await _shareInbox.dismissShare(me, share.id);
  }

  /// Ouvre l'element concerne par un lien vinland:// ou un partage recu en
  /// boite de reception -- meme resolution/navigation dans les deux cas
  /// (voir DeepLinkService, qui appelle cette methode). Retourne false si
  /// l'element est introuvable (id invalide, playlist privee inaccessible...).
  Future<bool> openSharedItem({required String type, required String id}) async {
    switch (type) {
      case 'track':
        final track = _findSharedTrack(id);
        if (track == null) return false;
        await playTrack(track);
        pushOverlay(const PlayerScreen());
        return true;
      case 'album':
        final album = _findSharedAlbum(id);
        if (album == null) return false;
        final openAlbum = onDesktopOpenAlbum;
        if (openAlbum != null) {
          openAlbum(album);
        } else {
          pushOverlay(AlbumScreen(album: album));
        }
        return true;
      case 'playlist':
        final playlist = await _findSharedPlaylist(id);
        if (playlist == null) return false;
        final openPlaylist = onDesktopOpenPlaylist;
        if (openPlaylist != null) {
          openPlaylist(playlist);
        } else {
          pushOverlay(PlaylistScreen(
            playlist: playlist,
            readOnly: !playlist.isOwnedByCurrentUser,
          ));
        }
        return true;
      default:
        return false;
    }
  }

  Track? _findSharedTrack(String id) {
    for (final t in allTracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Album? _findSharedAlbum(String id) {
    for (final a in albums) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<Playlist?> _findSharedPlaylist(String id) async {
    // Un lien partage porte l'id SERVEUR (voir playlistShareId dans
    // deep_link_service.dart), pas l'id local -- comparer aussi serverId
    // pour que le proprietaire retrouve sa propre playlist en rouvrant son
    // propre lien (les deux id different des qu'une playlist est synchronisee).
    for (final p in playlists) {
      if (p.id == id || p.serverId == id) return p;
    }
    Playlist? searchFriends() {
      for (final f in friends) {
        for (final p in f.playlists) {
          if (p.id == id) return p;
        }
        if (f.likesPlaylist?.id == id) return f.likesPlaylist;
        if (f.recentPlaysPlaylist?.id == id) return f.recentPlaysPlaylist;
      }
      return null;
    }
    final found = searchFriends();
    if (found != null) return found;
    // Pas trouvee dans le cache actuel : peut-etre juste pas encore
    // rafraichi depuis que l'ami a partage/publie cette playlist (le cache
    // n'est reactualise qu'a l'ouverture de l'onglet Amis) -- un seul
    // rechargement avant d'abandonner, pas a chaque appel.
    if (!loadingFriends) {
      await loadFriends();
      return searchFriends();
    }
    return null;
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

  /// Extrait une couleur d'ambiance via PaletteGenerator (deja une
  /// dependance du projet, jusque-la inutilisee) : quantifie l'image
  /// entiere et ponderee par population/saturation, plutot que l'ancienne
  /// moyenne brute de 5 pixels fixes (centre + coins), qui pouvait tomber
  /// sur un detail non representatif et produire une couleur "boueuse"
  /// n'apparaissant nulle part sur la cover.
  ///
  /// La swatch "vibrant" (la plus saturee) est preferee a la "dominant"
  /// (la plus etendue en surface) : sur une cover typique -- fond sombre
  /// uni + logo/texte colore au centre -- la dominante par surface est
  /// justement ce fond sombre, qui se fond avec le noir de l'ecran une fois
  /// assombri et donne l'impression que la couleur ne represente pas du
  /// tout la pochette (retour utilisateur). La vibrante capture l'accent
  /// coloré qui rend vraiment la cover reconnaissable.
  Future<Color?> _extractDominantColorIsolate(String coverPath) async {
    try {
      final ImageProvider provider = coverPath.startsWith('http')
          ? NetworkImage(coverPath) as ImageProvider
          : FileImage(File(coverPath));
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(100, 100),
      );
      return palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.mutedColor?.color;
    } catch (_) {
      return null;
    }
  }

  void _updateDominantColor(String? coverPath) {
    if (coverPath == null) {
      debugPrint('PALETTE: coverPath null');
      dominantColor = null;
      _notify();
      return;
    }
    if (_colorCache.containsKey(coverPath)) {
      debugPrint('PALETTE: cache hit');
      dominantColor = _colorCache[coverPath];
      _notify();
      return;
    }
    final requestId = ++_lastColorRequest;
    debugPrint('PALETTE: start extraction (isolate)');
    _extractDominantColorIsolate(coverPath).then((color) {
      if (_isDisposed) return;
      debugPrint('PALETTE: done, color=$color');
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
      // Reconfigurer depuis Parametres (changement de compte/serveur) peut
      // arriver sans passer par logout() d'abord -- meme nettoyage de
      // session Jam necessaire ici, voir logout().
      unawaited(_jam.leave());
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
  Future<void> syncRecentlyAdded({int albumCount = 5}) async {
    await _music.syncRecentlyAdded(albumCount: albumCount);
    _notify();
  }

  final _downloadWorker = DownloadWorkerService();

  // Taille max d'un lot d'upload (voir importLocalFilesToPlaylist) : garde
  // une marge confortable sous MAX_IMPORT_BODY_BYTES cote worker (500 Mo par
  // defaut, voir download-worker/server.py) pour ne jamais s'en approcher,
  // et evite une seule requete HTTP de plusieurs centaines de Mo/Go pour un
  // gros import (bibliotheque "titres likes" d'un ami) -- fragile (un seul
  // hoquet reseau perd tout le lot) et gourmande en RAM cote NAS (le worker
  // lit tout le corps de la requete en memoire).
  static const int _importBatchMaxBytes = 150 * 1024 * 1024;
  static const int _importBatchMaxFiles = 50;

  /// Lit (artiste, titre) depuis les tags locaux du fichier (MetadataGod,
  /// meme lib que MusicService.parseFile), ou null si illisibles/absents --
  /// utilise pour reperer un doublon avant meme d'uploader (voir
  /// _splitAlreadyInLibrary). Pas de repli sur le nom de fichier ici
  /// (contrairement au worker cote NAS) : un faux-negatif se contente
  /// d'uploader normalement, alors qu'un faux-positif sur un nom de fichier
  /// ambigu ferait sauter silencieusement un vrai import.
  Future<(String, String)?> _readLocalTags(File file) async {
    try {
      final metadata = await MetadataGod.readMetadata(file: file.path);
      final artist = metadata.artist;
      final title = metadata.title;
      if (artist != null &&
          artist.isNotEmpty &&
          title != null &&
          title.isNotEmpty) {
        return (artist, title);
      }
    } catch (_) {
      // Tags illisibles -- traite comme "pas de dedup possible" plus bas.
    }
    return null;
  }

  /// Separe [files] entre ceux deja presents dans la bibliotheque NAS
  /// (tags locaux correspondant a un Track deja synchronise, meme
  /// comparateur flou que l'import CSV -- MatchingService) et ceux a
  /// effectivement uploader. Evite de dupliquer un fichier deja sur le NAS
  /// (espace disque limite -- voir le RAID1 de l'utilisateur, 1 To
  /// utilisable) au prix d'un aller-retour de lecture de tags local, sans
  /// appel reseau.
  Future<
      (
        List<File> toUpload,
        List<String> alreadyPresentTrackIds,
      )> _splitAlreadyInLibrary(List<File> files) async {
    final toUpload = <File>[];
    final alreadyPresentTrackIds = <String>[];
    for (final file in files) {
      final tags = await _readLocalTags(file);
      Track? existing;
      if (tags != null) {
        final (artist, title) = tags;
        for (final t in allTracks) {
          if (MatchingService.titlesMatch(t.title, title) &&
              MatchingService.artistsMatch(t.artist, artist, strict: true)) {
            existing = t;
            break;
          }
        }
      }
      if (existing != null) {
        alreadyPresentTrackIds.add(existing.id);
      } else {
        toUpload.add(file);
      }
    }
    return (toUpload, alreadyPresentTrackIds);
  }

  /// Decoupe [files] en lots d'au plus _importBatchMaxBytes / _importBatchMaxFiles
  /// (ce qui vient en premier), pour que chaque upload reste une requete HTTP
  /// raisonnable -- voir importLocalFilesToPlaylist.
  Future<List<List<File>>> _batchFilesForImport(List<File> files) async {
    final batches = <List<File>>[];
    var current = <File>[];
    var currentBytes = 0;
    for (final file in files) {
      final size = await file.length();
      if (current.isNotEmpty &&
          (currentBytes + size > _importBatchMaxBytes ||
              current.length >= _importBatchMaxFiles)) {
        batches.add(current);
        current = [];
        currentBytes = 0;
      }
      current.add(file);
      currentBytes += size;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  /// Upload des fichiers audio locaux vers le NAS (download-worker POST
  /// /imports : ecrit dans _manual-imports/, declenche+attend un scan
  /// Navidrome, retrouve le song_id de chaque fichier), puis ajoute les
  /// morceaux retrouves a une playlist (nouvelle ou existante) ou aux titres
  /// likes. Voir ImportReviewScreen (mobile) et DesktopImportView (desktop)
  /// pour l'UI de selection des fichiers.
  ///
  /// Fait un lot d'uploads plutot qu'une seule requete geante (voir
  /// _batchFilesForImport) : un lot en echec (upload ou scan rate) n'annule
  /// pas les autres, ses fichiers sont juste comptes comme non retrouves.
  ///
  /// Retourne null seulement si AUCUN lot n'a pu etre envoye du tout (NAS
  /// injoignable des le premier essai, download-worker non configure...) ;
  /// sinon un compte de morceaux ajoutes + la liste de ceux non retrouves
  /// (tags illisibles, lot en echec...), a signaler a l'utilisateur plutot
  /// qu'a ignorer.
  Future<LocalImportResult?> importLocalFiles({
    required List<File> files,
    String? existingPlaylistId,
    String? newPlaylistName,
    bool addToLiked = false,
  }) async {
    assert(addToLiked
        ? (existingPlaylistId == null && newPlaylistName == null)
        : (existingPlaylistId == null) != (newPlaylistName == null));

    final (toUpload, dedupTrackIds) = await _splitAlreadyInLibrary(files);

    final batches = await _batchFilesForImport(toUpload);
    final uploadedTrackIds = <String>[];
    final unmatched = <String>[];
    var anyBatchSucceeded = false;

    for (final batch in batches) {
      final jobId = await _downloadWorker.uploadImportFiles(batch);
      if (jobId == null) {
        unmatched.addAll(batch.map((f) => p.basename(f.path)));
        continue;
      }
      final status = await _downloadWorker.waitForImportCompletion(jobId);
      if (status.state != DownloadJobState.done) {
        unmatched.addAll(batch.map((f) => p.basename(f.path)));
        continue;
      }
      anyBatchSucceeded = true;
      uploadedTrackIds
          .addAll(status.files.where((f) => f.trackId != null).map((f) => f.trackId!));
      unmatched.addAll(status.files
          .where((f) => f.trackId == null)
          .map((f) => f.originalFilename));
    }

    // Echec total seulement si rien n'a pu etre uploade ET qu'aucun doublon
    // local n'a ete detecte -- un doublon detecte avant upload reste un
    // resultat exploitable meme si le NAS est injoignable pour le reste.
    if (!anyBatchSucceeded && dedupTrackIds.isEmpty) return null;

    if (anyBatchSucceeded) {
      // Un import en masse (ex: toute la bibliotheque "titres likes" d'un
      // ami) peut toucher bien plus de 5 albums recents (defaut) une fois
      // que Navidrome regroupe par tags ID3 -- au pire un album par fichier.
      await syncRecentlyAdded(albumCount: min(200, max(5, toUpload.length)));
    }

    final allTrackIds = [...dedupTrackIds, ...uploadedTrackIds];

    if (addToLiked) {
      for (final id in allTrackIds) {
        // toggleLike inverse l'etat actuel : un morceau tout juste uploade
        // n'est jamais deja like, mais un doublon detecte localement
        // (dedupTrackIds) pointe vers un Track existant qui peut deja
        // l'etre -- ne togger que s'il ne l'est pas encore, sinon on le
        // retirerait des titres likes au lieu de l'y laisser.
        final track = _findTrackById(id);
        if (track != null && !track.isLiked) {
          await toggleLike(id);
        }
      }
    } else {
      final playlistId =
          existingPlaylistId ?? await createPlaylist(newPlaylistName!);
      for (final id in allTrackIds) {
        await addToPlaylist(playlistId, id);
      }
    }

    return LocalImportResult(
      matchedCount: allTrackIds.length,
      unmatchedFilenames: unmatched,
      duplicateSkippedCount: dedupTrackIds.length,
    );
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
