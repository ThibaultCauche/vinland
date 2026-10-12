import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../controllers/player_controller.dart';
import '../data/track_repository.dart';
import '../domain/home_shelves.dart';
import '../domain/liked_tracks.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../models/friend_profile.dart';
import '../models/collab_playlist.dart';
import '../models/pinned_item.dart';
import '../navigation/overlay_navigator.dart';
import '../services/music_service.dart';
import '../services/audio_handler.dart';
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
import '../services/local_import_planner.dart';
import '../services/share_inbox_service.dart';
import '../desktop/desktop_theme.dart';
import '../theme/mobile_theme.dart';
import '../theme/solid_color_effect.dart';
import '../theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final MusicService _music = MusicService();
  final VinlandAudioHandler _audioHandler;
  final JamService _jam = JamService();
  late final TrackRepository _tracks = MusicServiceTrackRepository(_music);
  final ThemeController _theme = ThemeController();
  final OverlayNavigator _navigator = OverlayNavigator();

  bool get isJamActive => _jam.isActive;
  bool get isJamHost => _jam.isHost;
  String? get jamSessionId => _jam.sessionId;
  int jamParticipantCount = 0;

  /// Pseudos des participants actuels (voir JamService.participantsStream),
  /// utilise pour le picker "Ceder l'hebergement" (voir showJamMenu). Vide
  /// hors session ou tant qu'on n'est pas hote.
  List<String> jamParticipantUsernames = [];

  /// Exclut son propre pseudo : les autres appareils du meme compte suivent
  /// silencieusement en synchro perso (voir isPersonalSyncParticipant) et
  /// partagent donc le meme pseudo Navidrome que l'hote -- jamais une cible
  /// valide pour un transfert d'hebergement (ils ne jouent jamais l'audio
  /// localement, voir _applyPersonalSyncState).
  List<String> get jamTransferTargets =>
      jamParticipantUsernames.where((u) => u != _navidrome.username).toList();

  StreamSubscription? _jamStateSub;
  StreamSubscription? _jamHostLeftSub;
  StreamSubscription? _jamCountSub;
  StreamSubscription? _jamParticipantsSub;
  StreamSubscription? _jamCommandSub;
  StreamSubscription? _jamRoleChangeSub;
  Timer? _jamHeartbeat;
  Timer? _personalSyncPoll;
  Timer? _nowPlayingHeartbeat;
  bool _applyingJamState = false;

  /// Cadence de rattrapage de derive entre l'hote et les participants (voir
  /// _broadcastJamState/_applyJamState). Descendu de 5s a 2s (retour
  /// utilisateur : leger decalage constant percu entre deux appareils) --
  /// ponytail: une partie de ce decalage vient probablement de la latence
  /// audio propre a chaque appareil (pilote/materiel), que ce recalage ne
  /// peut pas corriger ; si quelques dizaines de ms restent perceptibles
  /// apres ce changement, la prochaine etape serait un ajustement fin de la
  /// vitesse de lecture plutot qu'un seek periodique.
  static const _jamHeartbeatInterval = Duration(seconds: 2);

  // Synchro multi-appareils "perso" (voir _maybeBecomePersonalHost /
  // _tryJoinPersonalSync) : reutilise le relais Jam mais avec une session
  // deterministe par compte (pas de code a partager) et, cote participant,
  // affichage + controle a distance seulement -- l'audio n'est jamais joue
  // en double, contrairement au Jam "entre amis" classique.
  bool _personalSyncMode = false;
  Track? remoteTrack;
  bool remoteIsPlaying = false;
  String? remoteDeviceName;
  Duration? _remotePosition;
  bool get isPersonalSyncParticipant =>
      _personalSyncMode && isJamActive && !isJamHost;
  bool get isPersonalSyncHost => _personalSyncMode && isJamHost;

  /// Nom de l'appareil participant actuellement connecte a NOTRE synchro
  /// perso (voir isPersonalSyncHost) -- annonce par lui via la commande
  /// 'announce_device' (voir _announceDeviceToHost/_applyJamCommand), pas
  /// connu du relais (voir jam_relay/, qui ne suit que des pseudos, memes
  /// pour tous les appareils du meme compte). Sert uniquement a afficher
  /// "Connecte : <appareil>" dans showDeviceMenu -- le controle a distance
  /// marche deja sans ca, c'est juste pour que l'hote voie que l'autre
  /// appareil l'a bien detecte (retour utilisateur : "je ne vois pas le PC
  /// alors qu'il controle deja ma lecture").
  String? connectedParticipantDeviceName;

  String get _deviceLabel {
    if (Platform.isAndroid) return 'Téléphone';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isWindows) return 'PC';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isLinux) return 'Linux';
    return 'Appareil';
  }

  // Lecture locale et file d'attente : voir PlayerController. Accesseurs
  // gardes ici le temps de migrer les ecrans.
  late final PlayerController _player;
  PlayerController get playerController => _player;
  Track? get currentTrack => _player.currentTrack;
  bool get isPlaying => _player.isPlaying;
  Duration get position => _player.position;
  Duration get duration => _player.duration;
  List<Track> get queue => _player.queue;
  bool get isShuffled => _player.isShuffled;
  LoopMode get loopMode => _player.loopMode;
  bool get isRepeatEnabled => _player.isRepeatEnabled;

  // UI state
  int currentTab = 0;
  String searchQuery = '';
  bool showSearchResults = false;
  // displayTrack (pas currentTrack) : c'est le titre reellement affiche dans
  // le mini/plein lecteur (voir displayTrack), celui d'un autre appareil en
  // synchro perso participant y compris -- sinon le coeur "like" y refletait
  // currentTrack (local, perime/vide en participant) au lieu du titre
  // vraiment montre a l'ecran.
  bool get isCurrentTrackLiked =>
      displayTrack != null &&
      _music.likedTracks.any((t) => t.id == displayTrack!.id);
  bool get isCurrentTrackSuperLiked =>
      displayTrack != null &&
      _music.likedTracks.any((t) => t.id == displayTrack!.id && t.superLiked);

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

  /// Comme [likedTracks], plus un titre "fantome" par titre importe
  /// introuvable sur le NAS (voir likedWithMissing) : pour l'affichage de la
  /// page "Titres likes" seulement.
  List<Track> get likedTracksWithMissing =>
      likedWithMissing(likedTracks, _music.missingTracks);

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

  // Etageres "suggestions" de l'accueil (voir HomeShelves) : calculees une
  // fois et mises en cache ici plutot qu'a chaque build de l'accueil.
  HomeShelves _homeShelves = const HomeShelves();
  List<Track> get homeWeeklyTracks => _homeShelves.weeklyTracks;
  List<(String artist, String? coverPath)> get homeTopArtists =>
      _homeShelves.topArtists;
  List<Album> get homeDiscoveryAlbums => _homeShelves.discoveryAlbums;
  List<Album> get homeNewOnServerAlbums => _homeShelves.newOnServerAlbums;

  /// Volontairement PAS appele a chaque lot recu pendant une synchro (voir
  /// le garde dans _notify) : sinon, comme allTracks/albums grossissent en
  /// continu le temps que la synchro se termine, ces suggestions (notamment
  /// le melange aleatoire de "Decouverte", cense rester stable sur une
  /// journee) changeaient sans arret pendant tout le chargement au lieu de
  /// rester stables, remplacant ce qui etait deja affiche a l'utilisateur.
  void _refreshHomeShelves() =>
      _homeShelves = HomeShelves.compute(allTracks, albums);

  // Vrai tant que le tout premier chargement (cache local + tentative de
  // connexion Navidrome) n'est pas termine : evite un flash de l'ecran de
  // connexion (ou un "mot de passe incorrect" trompeur) le temps que le ping
  // reseau vers le NAS reponde, ce qui peut prendre plusieurs secondes.
  bool _isInitializing = true;
  bool get isInitializing => _isInitializing;

  // DEBOUNCE : absorbe les notify en rafale
  Timer? _notifyDebounce;

  // Expose le player pour les widgets (MiniPlayer, PlayerScreen)
  PlayerEngine get player => _player.player;

  // Delegue la verification de cover au MusicService
  bool coverExists(String? path) => _music.coverExists(path);

  //navidrome
  final NavidromeService _navidrome = NavidromeService();
  bool _useNavidrome = true;
  bool get useNavidrome => _useNavidrome;

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

  Future<void> setAutoDownloadLikes(bool value) async {
    _autoDownloadLikes = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoDownloadLikes, value);
    _notify();
  }

  AppState({required VinlandAudioHandler audioHandler})
      : _audioHandler = audioHandler {
    _player = PlayerController(output: audioHandler, tracks: _tracks)
      ..onTrackLoading = ((track) => _theme.updateCoverColor(track.coverPath))
      ..onPlayingChanged = _syncNowPlayingMirror
      ..onEngineEvent = _broadcastJamState
      ..onTrackStarted = _onTrackStarted;
    _player.addListener(_notify);
    _theme.addListener(_notify);
    _navigator.addListener(_notify);

    _audioHandler.customActionStream.listen((action) {
      if (action == 'add_to_likes' && currentTrack != null) {
        toggleLike(currentTrack!.id);
      } else if (action == 'skip_next') {
        nextTrack();
      } else if (action == 'skip_previous') {
        previousTrack();
      }
    });
  }

  /// Un titre vient de demarrer localement (voir PlayerController).
  void _onTrackStarted(Track track) {
    _syncNowPlayingMirror();
    // Voir NavidromeService.scrobble : fait remonter la lecture au NAS pour
    // que la regle de suppression des morceaux peu ecoutes puisse s'appuyer
    // dessus. Ids locaux/hors-Navidrome (assets, imports) n'ont pas
    // d'equivalent cote serveur, on ne les envoie pas.
    if (track.id.startsWith('navidrome_')) {
      unawaited(_navidrome.scrobble(track.id));
    }
    // Prend/garde le role d'hote de la synchro perso multi-appareils (voir
    // _maybeBecomePersonalHost) tant qu'aucune session Jam entre amis
    // manuelle n'est en cours -- diffuse aussi l'etat si deja hote.
    unawaited(_maybeBecomePersonalHost());
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

  // Navigation plein page mobile : voir OverlayNavigator.
  OverlayNavigator get navigator => _navigator;
  List<Widget> get overlayStack => _navigator.stack;
  Widget? get currentOverlay => _navigator.current;
  void pushOverlay(Widget screen) => _navigator.push(screen);
  void popOverlay() => _navigator.pop();
  void clearOverlays() => _navigator.clear();

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
    // Tout ce bloc doit rester dans ce try/finally : une exception non
    // rattrapee ici (cache local corrompu, plugin qui echoue au premier
    // appel...) interrompait initialize() avant la ligne qui bascule
    // _isInitializing a false, laissant le splash tourner indefiniment --
    // seul un kill+relance forcait un nouvel essai. Desormais l'app
    // s'affiche quand meme (au pire degradee) plutot que de rester bloquee.
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoDownloadLikes = prefs.getBool(_keyAutoDownloadLikes) ?? false;
      await _theme.load();

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
      await _player.restore(prefs);

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
    } catch (e, stack) {
      debugPrint('AppState.initialize failed, showing app anyway: $e\n$stack');
    } finally {
      // Rien de plus a attendre pour afficher l'app : "rester connecte" veut
      // dire ne jamais bloquer l'affichage sur un ping reseau. L'authentification
      // live (jusqu'a 10s si le NAS est lent/injoignable) et la resynchro se
      // font en fond.
      _isInitializing = false;
      _notify();
    }

    unawaited(_navidrome.authenticate().then((navidromeOk) {
      if (navidromeOk) {
        // Les URLs des titres en cache sont reconstruites a la demande avec
        // l'URL de serveur courante (voir SubsonicRefs) : rien a rafraichir,
        // un simple rebuild suffit.
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

  // Apparence (themes de fond, couleur d'ambiance) : voir ThemeController.
  DesktopThemeMode get desktopThemeMode => _theme.desktopThemeMode;
  Color get desktopThemeColor => _theme.desktopThemeColor;
  double get desktopCoverBlurSigma => _theme.desktopCoverBlurSigma;
  SolidColorEffect get desktopSolidEffect => _theme.desktopSolidEffect;
  String? get desktopPinnedCoverPath => _theme.desktopPinnedCoverPath;
  MobileThemeMode get mobileThemeMode => _theme.mobileThemeMode;
  Color get mobileThemeColor => _theme.mobileThemeColor;
  double get mobileCoverBlurSigma => _theme.mobileCoverBlurSigma;
  SolidColorEffect get mobileSolidEffect => _theme.mobileSolidEffect;
  String? get mobilePinnedCoverPath => _theme.mobilePinnedCoverPath;
  Color? get dominantColor => _theme.dominantColor;
  Future<void> setDesktopThemeMode(DesktopThemeMode mode) =>
      _theme.setDesktopThemeMode(mode);
  Future<void> setDesktopThemeColor(Color color) =>
      _theme.setDesktopThemeColor(color);
  Future<void> setDesktopCoverBlurSigma(double sigma) =>
      _theme.setDesktopCoverBlurSigma(sigma);
  Future<void> setDesktopSolidEffect(SolidColorEffect effect) =>
      _theme.setDesktopSolidEffect(effect);
  Future<void> setDesktopPinnedCoverPath(String? path) =>
      _theme.setDesktopPinnedCoverPath(path);
  Future<void> setMobileThemeMode(MobileThemeMode mode) =>
      _theme.setMobileThemeMode(mode);
  Future<void> setMobileThemeColor(Color color) =>
      _theme.setMobileThemeColor(color);
  Future<void> setMobileCoverBlurSigma(double sigma) =>
      _theme.setMobileCoverBlurSigma(sigma);
  Future<void> setMobileSolidEffect(SolidColorEffect effect) =>
      _theme.setMobileSolidEffect(effect);
  Future<void> setMobilePinnedCoverPath(String? path) =>
      _theme.setMobilePinnedCoverPath(path);

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
    final lastFull = lastFullMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lastFullMs)
        : null;
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
        // Synchro ratee (NAS coupe en cours de route) : on ne note pas la
        // date, pour retenter au prochain lancement au lieu d'attendre 6h.
        final ok = await _music.syncWithNavidrome(onProgress: _notify);
        if (ok) {
          await prefs.setInt(
              _keyLastFullSyncAt, DateTime.now().millisecondsSinceEpoch);
        }
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

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _notifyDebounce?.cancel();
    _jamHeartbeat?.cancel();
    _nowPlayingHeartbeat?.cancel();
    _personalSyncPoll?.cancel();
    _jamStateSub?.cancel();
    _jamHostLeftSub?.cancel();
    _jamCountSub?.cancel();
    _jamParticipantsSub?.cancel();
    _jamCommandSub?.cancel();
    _jamRoleChangeSub?.cancel();
    unawaited(_jam.leave());
    _player.dispose();
    _theme.dispose();
    _navigator.dispose();
    _audioHandler.player.dispose();
    super.dispose();
  }

  Future<void> scanMusic(String path) async {
    await _music.scanDirectory(path);
    _notify();
  }

  Future<void> logout() async {
    // Voir PlayerController.stopOutput : ne doit jamais empecher la
    // deconnexion, meme si le service audio est dans un mauvais etat.
    await _player.stopOutput();
    // Sans ca, une session Jam active survivait a la deconnexion : le compte
    // qui se reconnecte ensuite (ou un simple changement de compte, meme
    // mecanisme) heritait d'une session WebSocket ouverte sous une identite
    // qui n'est plus la sienne (voir dispose(), qui fait deja ce nettoyage a
    // la fermeture complete de l'app -- logout() doit faire pareil).
    unawaited(_jam.leave());
    _nowPlayingHeartbeat?.cancel();
    _nowPlayingHeartbeat = null;
    _music.updateNowPlaying(null);
    await _navidrome.clearCredentials();
    _music.setCurrentUser(null);
    SearchHistoryService().setCurrentUser(null);
    await _player.reset();
    _notify();
  }

  /// Lance `track` et construit la file d'attente a partir de `trackList`
  /// (le contexte -- album, playlist, titres likes, artiste...) : tout ce
  /// qui suit `track` dans cette liste devient `queue` (melange une fois si
  /// la lecture aleatoire est active). `trackList` devient aussi l'ordre
  /// d'origine (voir PlayQueue), reutilise pour regenerer la file quand
  /// elle s'epuise ou qu'on (re)bascule le mode aleatoire.
  Future<void> playTrack(Track track, {List<Track>? trackList}) async {
    // Participant de synchro perso (voir isPersonalSyncParticipant) : ne
    // joue jamais ce titre localement (ce qui aurait silencieusement pris
    // le role d'hote, voir _maybeBecomePersonalHost) -- demande plutot a
    // l'appareil deja actif de le jouer, lui (retour utilisateur : "vice
    // versa", changer de titre depuis n'importe quel appareil doit piloter
    // celui qui joue vraiment, pas en prendre le controle).
    if (isPersonalSyncParticipant && !_applyingJamState) {
      remotePlayTrack(track);
      return;
    }
    // Participant d'une session Jam entre amis (pas hote) : suit
    // passivement l'etat recu du relais (voir _applyJamState), ne pilote
    // jamais la lecture lui-meme -- sauf l'appel interne fait par
    // _applyJamState, qui doit pouvoir passer.
    if (isJamActive && !isJamHost && !_applyingJamState) {
      return;
    }
    await _player.playTrack(track, trackList: trackList);
  }

  /// Republie l'etat "now playing" (MusicService.updateNowPlaying) a chaque
  /// vrai changement lecture/pause -- pas seulement au changement de titre
  /// (voir _onTrackStarted) -- pour que l'onglet Amis d'un ami reflete une pause
  /// au lieu de garder affiche indefiniment le dernier titre charge. Tant
  /// que la lecture continue sur le meme titre, un battement toutes les 60s
  /// rafraichit le mirroir cote serveur pour que fetchFriends (seuil de
  /// 2 min, voir MusicService._nowPlayingStaleAfter) ne le traite jamais
  /// comme perime alors qu'on ecoute toujours.
  void _syncNowPlayingMirror() {
    _nowPlayingHeartbeat?.cancel();
    _nowPlayingHeartbeat = null;
    if (!isPlaying || currentTrack == null) {
      _music.updateNowPlaying(null);
      return;
    }
    _music.updateNowPlaying(currentTrack!.id,
        jamSessionId: isJamHost ? jamSessionId : null);
    _nowPlayingHeartbeat = Timer.periodic(const Duration(seconds: 60), (_) {
      if (currentTrack != null) {
        _music.updateNowPlaying(currentTrack!.id,
            jamSessionId: isJamHost ? jamSessionId : null);
      }
    });
  }

  void togglePlayPause() {
    if (isPersonalSyncParticipant) {
      remoteToggle();
      return;
    }
    if (isJamActive && !isJamHost && !_applyingJamState) {
      return;
    }
    // Redemarrage de l'app (aucune source chargee) : PlayerController
    // relance une vraie lecture du dernier titre, sans rien diffuser ici.
    if (_player.togglePlayPause() && isJamHost) _broadcastJamState();
  }

  Future<void> nextTrack() async {
    if (isPersonalSyncParticipant) {
      remoteNext();
      return;
    }
    if (isJamActive && !isJamHost) return;
    await _player.next();
  }

  /// Avant 3s de lecture : revient au titre precedent (file d'attente
  /// remise en tete). Au-dela : redemarre simplement le titre en cours,
  /// comme la plupart des lecteurs.
  Future<void> previousTrack() async {
    if (isPersonalSyncParticipant) {
      remotePrevious();
      return;
    }
    if (isJamActive && !isJamHost) return;
    await _player.previous();
  }

  /// Saute directement au titre en position `index` de la file d'attente :
  /// tout ce qui le precedait dans `queue` est abandonne (jamais joue, donc
  /// pas ajoute a l'historique).
  Future<void> playFromQueue(int index) => _player.playFromQueue(index);

  /// "Ajouter a la file d'attente" (options d'un titre) : le place a la fin
  /// de `queue`. Participant d'un Jam (pas hote) : `queue` locale n'est
  /// jamais lue tant qu'on suit un hote (voir playTrack/PlayerController), donc
  /// on relaie la demande a l'hote via le canal command (voir
  /// _applyJamCommand) plutot que de se contenter d'un ajout local inerte.
  void addToQueue(Track track) {
    if (isJamActive && !isJamHost) {
      _jam.sendCommand('queue_add', trackId: track.id);
    }
    _player.addToQueue(track);
  }

  /// "Lire ensuite" (options d'un titre) : le place en tete de `queue`, donc
  /// juste apres le titre en cours -- contrairement a addToQueue qui l'ajoute
  /// a la fin. Pour mettre plusieurs titres en file en une fois (ex: un album
  /// entier), appeler dans l'ordre inverse voulu (le dernier insere en tete
  /// se retrouve premier). Meme relais vers l'hote qu'addToQueue en
  /// participant de Jam.
  void playNext(Track track) {
    if (isJamActive && !isJamHost) {
      _jam.sendCommand('play_next', trackId: track.id);
    }
    _player.playNext(track);
  }

  void removeFromQueue(int index) => _player.removeFromQueue(index);

  /// Reordonnancement par glisser-deposer (voir QueueScreen) : `newIndex`
  /// suit la convention de ReorderableListView.onReorder (index cible avant
  /// le retrait de l'element deplace).
  void reorderQueue(int oldIndex, int newIndex) =>
      _player.reorderQueue(oldIndex, newIndex);

  void seek(Duration pos) {
    if (isPersonalSyncParticipant) {
      remoteSeek(pos);
      return;
    }
    if (isJamActive && !isJamHost && !_applyingJamState) {
      return;
    }
    _player.seek(pos);
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
    _remotePosition = null;
    final id = _jam.generateSessionId();
    final ok = await _jam.host(id);
    if (!ok) return null;
    _wireAsJamHost();
    _listenForHostTransfer();
    _broadcastJamState();
    if (currentTrack != null) {
      _syncNowPlayingMirror();
    }
    _notify();
    return id;
  }

  /// Abonnements communs a toute prise du role d'hote (demarrage explicite,
  /// synchro perso, ou promotion via un transfert -- voir
  /// _applyHostTransfer) : compteur/pseudos des participants, commandes a
  /// distance (play/pause, ajout a la file), battement de resynchronisation.
  void _wireAsJamHost() {
    _jamCountSub?.cancel();
    _jamCountSub = _jam.participantCountStream.listen((count) {
      jamParticipantCount = count;
      // Un participant qui vient de rejoindre n'a jamais reçu la file
      // d'attente : force son renvoi au prochain battement (voir
      // _broadcastJamState) meme si son contenu n'a pas change depuis le
      // dernier envoi aux participants deja presents.
      _lastBroadcastQueueIds = null;
      // Plus personne connecte : oublie l'appareil annonce precedemment
      // (voir connectedParticipantDeviceName) -- sinon showDeviceMenu
      // continuait d'afficher "Connecte : Téléphone" longtemps apres sa
      // deconnexion.
      if (count == 0) connectedParticipantDeviceName = null;
      _notify();
    });
    _jamParticipantsSub?.cancel();
    _jamParticipantsSub = _jam.participantsStream.listen((names) {
      jamParticipantUsernames = names;
      _notify();
    });
    // Sans ca, les commandes envoyees par les participants (play/pause a
    // distance, ajout a la file -- voir sendCommand/_applyJamCommand)
    // n'etaient recues que dans la synchro perso multi-appareils
    // (_becomePersonalHost, qui s'abonne deja a ce flux) : un vrai Jam entre
    // amis les ignorait silencieusement, l'hote ne les ecoutant jamais.
    _jamCommandSub?.cancel();
    _jamCommandSub = _jam.commandStream.listen(_applyJamCommand);
    _jamHeartbeat?.cancel();
    _jamHeartbeat =
        Timer.periodic(_jamHeartbeatInterval, (_) => _broadcastJamState());
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
    _listenForHostTransfer();
    _notify();
    return true;
  }

  void _listenForHostTransfer() {
    _jamRoleChangeSub?.cancel();
    _jamRoleChangeSub = _jam.hostTransferredStream.listen(_applyHostTransfer);
  }

  /// Cede l'hebergement a `targetUsername` (voir jamTransferTargets) --
  /// reserve a l'hote actuel. Les deux appareils bascule de role via
  /// _applyHostTransfer des que le relais confirme (voir
  /// JamService.hostTransferredStream) ; les autres participants ne
  /// remarquent que le prochain 'state' vient d'ailleurs.
  void transferJamHost(String targetUsername) {
    if (!isJamHost) return;
    _jam.sendTransferHost(targetUsername);
  }

  /// Bascule de role suite a un transfert d'hebergement confirme par le
  /// relais (voir transferJamHost/JamService.hostTransferredStream) : la
  /// session WebSocket reste la meme, seul le role change cote AppState --
  /// contrairement a startJamSession/joinJamSession, qui (re)ouvrent une
  /// connexion. L'audio ne s'interrompt jamais : le nouvel hote jouait deja
  /// localement ce titre en le suivant (voir _applyJamState), il continue
  /// simplement a le piloter au lieu de le suivre.
  void _applyHostTransfer(bool becameHost) {
    if (becameHost) {
      _jamStateSub?.cancel();
      _jamStateSub = null;
      _wireAsJamHost();
      _lastBroadcastQueueIds = null;
      _broadcastJamState();
    } else {
      // Ce callback est partage par deux cas bien distincts qui envoient
      // tous les deux un 'host_transferred' cote relais (voir le cas 'host'
      // dans jam_relay/bin/server.dart, "prise de controle" y compris) :
      // 1. un vrai transfert d'hebergement Jam entre amis (voir
      //    transferJamHost) -- celui qui le recoit doit redevenir un vrai
      //    suiveur Jam (isFriendJamActive, actions locales ignorees).
      // 2. un autre appareil du MEME compte qui "reprend ici" la synchro
      //    perso (voir takeOverPersonalSync/_maybeBecomePersonalHost) --
      //    celui-ci doit rester un participant de synchro perso normal
      //    (menu Peripheriques, remoteToggle/remoteNext...), pas basculer en
      //    suiveur Jam : sans cette distinction, l'appareil retrograde
      //    perdait _personalSyncMode (mis a false ci-dessous dans TOUS les
      //    cas avant ce fix) et donc isPersonalSyncParticipant, se
      //    retrouvant coince en suiveur Jam muet -- plus aucun controle,
      //    plus aucune detection de periphérique (retour utilisateur).
      // _personalSyncMode (avant d'etre modifie plus bas) est le seul signal
      // disponible pour les separer : vrai seulement si CET appareil etait
      // lui-meme l'hote de la synchro perso avant ce transfert.
      final wasPersonalHost = _personalSyncMode;
      _jamHeartbeat?.cancel();
      _jamHeartbeat = null;
      _jamCommandSub?.cancel();
      _jamCommandSub = null;
      _jamCountSub?.cancel();
      _jamCountSub = null;
      _jamParticipantsSub?.cancel();
      _jamParticipantsSub = null;
      jamParticipantCount = 0;
      jamParticipantUsernames = [];
      _jamStateSub?.cancel();
      if (wasPersonalHost) {
        _personalSyncMode = true;
        _jamStateSub = _jam.stateStream.listen(_applyPersonalSyncState);
        _jamHostLeftSub?.cancel();
        _jamHostLeftSub =
            _jam.hostLeftStream.listen((_) => _leavePersonalSync());
        _announceDeviceToHost();
      } else {
        _personalSyncMode = false;
        _jamStateSub = _jam.stateStream.listen(_applyJamState);
      }
    }
    _syncNowPlayingMirror();
    _notify();
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
    await _jamParticipantsSub?.cancel();
    _jamParticipantsSub = null;
    await _jamCommandSub?.cancel();
    _jamCommandSub = null;
    await _jamRoleChangeSub?.cancel();
    _jamRoleChangeSub = null;
    await _jam.leave();
    jamParticipantCount = 0;
    jamParticipantUsernames = [];
    if (wasHost && currentTrack != null) {
      _syncNowPlayingMirror();
    }
    _notify();
  }

  /// Vrai seulement pour une session Jam "entre amis" demarree/rejointe
  /// manuellement (menu Jam) -- exclut la synchro perso multi-appareils
  /// (silencieuse, jamais affichee dans ce menu). Utilise par
  /// jam_controls.dart et l'icone Jam de la barre de lecture desktop.
  bool get isFriendJamActive => isJamActive && !_personalSyncMode;

  /// Derniere file d'attente envoyee aux participants (voir
  /// _broadcastJamState) : evite de rerepeter potentiellement des milliers
  /// d'ids a chaque battement de 5s quand elle n'a pas change.
  List<String>? _lastBroadcastQueueIds;

  void _broadcastJamState() {
    if (!_jam.isActive || !_jam.isHost) return;
    final track = currentTrack;
    if (track == null) return;
    final currentQueueIds = queue.map((t) => t.id).toList();
    final queueChanged = !listEquals(_lastBroadcastQueueIds, currentQueueIds);
    if (queueChanged) _lastBroadcastQueueIds = currentQueueIds;
    _jam.sendState(
      trackId: track.id,
      positionMs: position.inMilliseconds,
      isPlaying: isPlaying,
      deviceName: _deviceLabel,
      queueIds: queueChanged ? currentQueueIds : null,
    );
  }

  /// Applique l'etat recu de l'hote (voir joinJamSession) : change de titre
  /// si besoin, rattrape la position (compensee du delai de transit reseau
  /// via le timestamp d'envoi), aligne play/pause, et reflete la vraie file
  /// d'attente de l'hote (voir msg.queueIds) -- sans ca, chaque participant
  /// gardait sa propre file locale, jamais reliee a ce qui joue vraiment
  /// (retour utilisateur : "chacun a sa file d'attente"). _applyingJamState
  /// laisse passer ces appels a travers les gardes de playTrack/seek/etc.
  /// qui bloquent sinon toute action de lecture locale pendant une session
  /// suivie.
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
      if (msg.queueIds != null) {
        _player.replaceQueue(
            msg.queueIds!.map(_findTrackById).whereType<Track>().toList());
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
    _personalSyncPoll = Timer.periodic(
        const Duration(seconds: 20), (_) => _tryJoinPersonalSync());
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
    _announceDeviceToHost();
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
    _remotePosition = Duration(milliseconds: msg.positionMs);
    _notify();
  }

  Future<void> _leavePersonalSync() async {
    _personalSyncMode = false;
    remoteTrack = null;
    remoteIsPlaying = false;
    remoteDeviceName = null;
    _remotePosition = null;
    await _jamStateSub?.cancel();
    _jamStateSub = null;
    await _jamHostLeftSub?.cancel();
    _jamHostLeftSub = null;
    await _jam.leave();
    _notify();
  }

  /// "Reprendre ici" depuis le menu Peripheriques (voir showDeviceMenu) :
  /// bascule le titre en cours d'ecoute sur un autre appareil du compte vers
  /// celui-ci, a la position ou l'autre appareil en etait. playTrack() prend
  /// deja seul l'hote de la synchro perso (voir _maybeBecomePersonalHost,
  /// appele par _onTrackStarted) des qu'on joue localement, exactement
  /// comme changer d'appareil actif dans Spotify Connect -- il suffit donc
  /// de lancer le titre distant puis de rattraper sa position.
  Future<void> takeOverPersonalSync() async {
    final track = remoteTrack;
    if (track == null) return;
    final resumePosition = _remotePosition;
    await playTrack(track);
    if (resumePosition != null && resumePosition > Duration.zero) {
      seek(resumePosition);
    }
  }

  /// Prend (ou garde) le role d'hote de la synchro perso a chaque lecture
  /// locale reelle (voir _onTrackStarted) -- jamais pendant une session Jam
  /// entre amis manuelle. C'est ce qui fait qu'appuyer sur play sur
  /// n'importe quel appareil du compte le rend autoritaire, exactement comme
  /// changer d'appareil actif dans Spotify Connect. Cette session (id prive,
  /// voir JamService.personalSessionId) est republiee dans le mirroir "now
  /// playing" (voir _syncNowPlayingMirror) des qu'elle est active : c'est ce
  /// qui rend n'importe quelle ecoute en cours rejoignable par un ami depuis
  /// la page Amis (bouton "Rejoindre") sans avoir a demarrer explicitement
  /// une session Jam -- "ecoute a la demande".
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
    _remotePosition = null;

    final id = _jam.personalSessionId(username);
    final ok = await _jam.host(id);
    if (!ok) return;
    _personalSyncMode = true;
    _wireAsJamHost();
    _listenForHostTransfer();
    _broadcastJamState();
    // Republie tout de suite avec le jamSessionId maintenant connu -- sans
    // ca, l'appel _syncNowPlayingMirror fait juste avant dans _onTrackStarted
    // (avant que ce host ne soit etabli) avait deja publie ce titre sans
    // session, et il fallait attendre jusqu'a 60s (le battement) avant qu'un
    // ami le voie comme rejoignable.
    _syncNowPlayingMirror();
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
      case 'queue_add':
      case 'play_next':
        final track = cmd.trackId == null ? null : _findTrackById(cmd.trackId!);
        if (track == null) return;
        if (cmd.action == 'play_next') {
          playNext(track);
        } else {
          addToQueue(track);
        }
        break;
      case 'play_track':
        // Changement de titre demande par un participant de synchro perso
        // (voir remotePlayTrack) : contrairement a queue_add/play_next, on
        // veut vraiment lancer ce titre tout de suite, comme si on l'avait
        // tape localement sur l'hote.
        final track = cmd.trackId == null ? null : _findTrackById(cmd.trackId!);
        if (track == null) return;
        playTrack(track);
        break;
      case 'seek':
        if (cmd.positionMs == null) return;
        seek(Duration(milliseconds: cmd.positionMs!));
        break;
      case 'announce_device':
        // Purement informatif (voir connectedParticipantDeviceName) : ne
        // pilote rien, juste pour que l'hote sache quel appareil le
        // controle deja (retour utilisateur).
        connectedParticipantDeviceName = cmd.deviceName;
        _notify();
        break;
    }
  }

  /// Fait savoir a l'hote quel appareil vient de le rejoindre en synchro
  /// perso (voir connectedParticipantDeviceName) -- appele juste apres
  /// chaque bascule vers le role de participant (_tryJoinPersonalSync et le
  /// cas "reprise" de _applyHostTransfer), jamais au demarrage d'un Jam
  /// entre amis (l'hote y connait deja tout le monde par pseudo).
  void _announceDeviceToHost() {
    _jam.sendCommand('announce_device', deviceName: _deviceLabel);
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

  void remoteSeek(Duration pos) {
    if (!isPersonalSyncParticipant) return;
    _jam.sendCommand('seek', positionMs: pos.inMilliseconds);
    // Anticipe localement (comme _applyJamState) au lieu d'attendre le
    // prochain battement de l'hote (jusqu'a 5s) pour que la barre de
    // progression reflete tout de suite le glissement.
    _remotePosition = pos;
    _notify();
  }

  /// "Changer de musique" a distance (voir showDeviceMenu/PlayerScreen) :
  /// demande a l'hote de lancer CE titre tout de suite, plutot que de le
  /// jouer localement -- contrairement a avant ce fix, un participant qui
  /// tapait un titre prenait silencieusement le role d'hote (voir
  /// _maybeBecomePersonalHost) au lieu de simplement piloter l'appareil deja
  /// actif, ce qui n'est pas ce qu'on attend d'une vraie ecoute Spotify
  /// Connect-like entre plusieurs appareils du meme compte (retour
  /// utilisateur).
  void remotePlayTrack(Track track) {
    if (!isPersonalSyncParticipant) return;
    _jam.sendCommand('play_track', trackId: track.id);
  }

  /// Ce qui doit s'afficher dans la barre de lecture (mini-player, plein
  /// ecran, barre desktop) : le titre/etat local normalement, mais celui de
  /// l'hote quand on est un participant de synchro perso (voir
  /// isPersonalSyncParticipant) -- rien ne joue localement dans ce cas, donc
  /// currentTrack/isPlaying/position locaux seraient perimes ou vides.
  Track? get displayTrack =>
      isPersonalSyncParticipant ? remoteTrack : currentTrack;
  bool get displayIsPlaying =>
      isPersonalSyncParticipant ? remoteIsPlaying : isPlaying;
  Duration get displayPosition =>
      isPersonalSyncParticipant ? (_remotePosition ?? Duration.zero) : position;

  Track? _findTrackById(String id) => _tracks.findById(id);

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

  /// Copie une playlist d'un ami (consultee en lecture seule, voir
  /// PlaylistScreen.readOnly) telle quelle dans sa propre bibliotheque : une
  /// nouvelle playlist a soi, avec les memes titres dans le meme ordre.
  /// N'importe quelle modification ulterieure (ajout/retrait/reordonnancement)
  /// n'affecte que cette copie, jamais l'originale de l'ami.
  Future<String> copyFriendPlaylist(Playlist source) async {
    final newId = await createPlaylist(source.name);
    for (final trackId in source.trackIds) {
      await addToPlaylist(newId, trackId);
    }
    return newId;
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

  /// Retrouve un ami par pseudo, chargeant la liste au besoin (ex: tap sur
  /// une tuile "recemment ecoute" de l'accueil avant meme d'avoir ouvert
  /// l'onglet Amis). Null si le compte n'existe plus / ne partage plus rien.
  Future<FriendProfile?> resolveFriend(String username) async {
    if (friends.isEmpty) await loadFriends();
    for (final f in friends) {
      if (f.username == username) return f;
    }
    return null;
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

  Track? findSharedTrack(String id) => _findTrackById(id);

  Album? findSharedAlbum(String id) {
    for (final a in albums) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<Playlist?> findSharedPlaylist(String id) async {
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

  /// 10 dernier(e)s album/playlist/artiste/ami ecoute(e)s, comme sur
  /// Spotify -- 10 plutot que 8 pour remplir exactement 2 lignes de 5 sur
  /// la grille desktop (retour utilisateur).
  List<RecentPlay> get recentPlays => _music.recentPlays.take(10).toList();

  void recordRecentPlay(RecentPlay entry) {
    _music.recordRecentPlay(entry);
    _notify();
  }

  List<PinnedItem> get pinnedItems => _music.pinnedItems;
  bool isPinned(PinnedItemType type, String id) => _music.isPinned(type, id);
  void togglePin(PinnedItem item) {
    _music.togglePin(item);
    _notify();
  }

  /// Fusionne les tuiles epinglees avec "recemment ecoute" pour la vitrine
  /// d'accueil (mobile ET desktop, meme logique des deux cotes) : les
  /// epingles apparaissent toujours en premier, sans jamais dupliquer une
  /// entree deja recemment ecoutee qui serait aussi epinglee.
  List<RecentPlay> get homeShelfEntries {
    final pinned = _music.pinnedItems.map((p) => RecentPlay(
          type: switch (p.type) {
            PinnedItemType.album => RecentPlayType.album,
            PinnedItemType.playlist => RecentPlayType.playlist,
            PinnedItemType.artist => RecentPlayType.artist,
          },
          id: p.id,
          title: p.title,
          // Repli pour les tuiles epinglees avant l'ajout de ce sous-titre
          // (deja synchronisees sans, subtitle: '' -- pas besoin de
          // depingler/repingler pour le voir apparaitre).
          subtitle: p.type == PinnedItemType.playlist &&
                  p.id == kLikedSongsRecentId &&
                  p.subtitle.isEmpty
              ? 'Playlist'
              : p.subtitle,
          playedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ));
    final pinnedKeys = pinned.map((p) => '${p.type.name}:${p.id}').toSet();
    final recent = _music.recentPlays
        .where((r) => !pinnedKeys.contains('${r.type.name}:${r.id}'));
    return [...pinned, ...recent].take(10).toList();
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

  /// A appeler (par tous les ecrans album/artiste/decouverte) juste apres
  /// qu'un DownloadWorkerService.waitForCompletion() renvoie "done" : fait
  /// syncRecentlyAdded() comme avant (rafraichit le reste de l'album/artiste
  /// autour), PUIS retrouve specifiquement ce titre via
  /// MusicService.findAndAdoptTrack en filet de securite -- un titre
  /// telecharge sans album connu partage un dossier avec les autres titres
  /// "sans album" du meme artiste deja telecharges, dont la date de creation
  /// Navidrome ne bouge plus des le 2e titre : il peut donc ne jamais
  /// apparaitre dans la fenetre "derniers ajouts" de syncRecentlyAdded seul
  /// (retour utilisateur : "impossible de telecharger" alors que le fichier
  /// existe bien cote NAS).
  Future<void> handleTrackDownloaded(String artist, String title,
      {int albumCount = 5}) async {
    await _music.syncRecentlyAdded(albumCount: albumCount);
    await _music.findAndAdoptTrack(artist, title);
    _notify();
  }

  final _downloadWorker = DownloadWorkerService();

  /// Upload des fichiers audio locaux vers le NAS (download-worker POST
  /// /imports : ecrit dans _manual-imports/, declenche+attend un scan
  /// Navidrome, retrouve le song_id de chaque fichier), puis ajoute les
  /// morceaux retrouves a une playlist (nouvelle ou existante) ou aux titres
  /// likes. Voir ImportReviewScreen (mobile) et DesktopImportView (desktop)
  /// pour l'UI de selection des fichiers.
  ///
  /// Fait un lot d'uploads plutot qu'une seule requete geante (voir
  /// batchFilesForImport) : un lot en echec (upload ou scan rate) n'annule
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

    final (toUpload, dedupTrackIds) =
        await splitAlreadyInLibrary(files, allTracks);

    final batches = await batchFilesForImport(toUpload);
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
      uploadedTrackIds.addAll(
          status.files.where((f) => f.trackId != null).map((f) => f.trackId!));
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

  Future<void> toggleShuffle() => _player.toggleShuffle();
  Future<void> toggleLoopMode() => _player.toggleLoopMode();

  Future<void> clearAllLikes() async {
    await _music.clearAllLikes();
    _notify();
  }
}
