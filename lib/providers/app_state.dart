import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../controllers/cast_controller.dart';
import '../controllers/jam_controller.dart';
import '../controllers/jam_sync_settings.dart';
import '../controllers/party_controller.dart';
import '../controllers/party_host_dj.dart';
import '../controllers/party_radio.dart';
import '../controllers/playback_settings.dart';
import '../controllers/player_controller.dart';
import '../data/track_repository.dart';
import '../domain/home_shelves.dart';
import '../domain/smart_playlists.dart';
import '../domain/listening_stats.dart';
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
import '../services/personal_sync_secret.dart';
import '../services/deep_link_service.dart';
import '../services/discovery_service.dart';
import '../services/matching_service.dart';
import '../services/party/party_link.dart';
import '../services/party/party_models.dart';
import '../services/party/party_socket.dart';
import '../controllers/blind_test_host.dart';
import '../controllers/party_environment.dart';
import '../services/bluetooth_trusted_devices_service.dart';
import '../services/avatar_service.dart';
import '../services/download_worker_service.dart';
import '../services/local_import_planner.dart';
import '../services/share_inbox_service.dart';
import '../services/lyrics_service.dart';
import '../services/cast/cast_receiver.dart';
import '../domain/lyrics.dart';
import '../services/media_browser.dart';
import '../desktop/desktop_theme.dart';
import '../theme/mobile_theme.dart';
import '../theme/solid_color_effect.dart';
import '../theme/theme_controller.dart';
import '../features/shared/library_port.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier
    with WidgetsBindingObserver
    implements LibraryPort {
  final MusicService _music;
  final NavidromeService _navidrome;
  final VinlandAudioHandler _audioHandler;
  late final TrackRepository _tracks = MusicServiceTrackRepository(_music);
  final ThemeController _theme = ThemeController();
  final OverlayNavigator _navigator = OverlayNavigator();

  // Jam entre amis et synchro perso : voir JamController. Accesseurs gardes
  // ici le temps de migrer les ecrans.
  /// Secret de synchro perso du compte (voir PersonalSyncSecretStore).
  late final PersonalSyncSecretStore _personalSecrets =
      PersonalSyncSecretStore(_navidrome);

  /// Paroles du titre en cours (Navidrome, sinon LRCLIB).
  late final LyricsService lyrics =
      LyricsService(navidromeLyrics: _navidrome.lyrics);

  Future<PersonalSyncIds?> _personalSyncIds(String username) async {
    final secret = await _personalSecrets.secretFor(username);
    return secret == null ? null : PersonalSyncIds.fromAccountSecret(secret);
  }

  late final JamController _jamCtl;
  JamController get jam => _jamCtl;
  bool get isJamActive => _jamCtl.isActive;
  bool get isJamHost => _jamCtl.isHost;
  String? get jamSessionId => _jamCtl.sessionId;
  int get jamParticipantCount => _jamCtl.participantCount;
  List<String> get jamTransferTargets => _jamCtl.transferTargets;

  // Mode Soiree : voir PartyController (protocole) et PartyHostDj (la file
  // de la soiree jouee par le lecteur de l'hote).
  late final PartyController party;

  /// Diffusion sur Chromecast, creee a la premiere ouverture de la liste
  /// des appareils.
  CastController get cast => _cast ??= CastController(output: _audioHandler)
    ..onReceiverReady = () {
      final track = currentTrack;
      if (track != null) unawaited(_sendCastExtras(track));
    };
  CastController? _cast;
  late final PartyHostDj _partyDj;
  // Partagee entre le mode Soiree et « Lancer la radio » (voir startRadio).
  late final PartyRadio _radio;
  late final PartyEnvironment partyEnvironment = PartyEnvironment(
    relayUrl: () => relayUrlFromServer(_navidrome.baseUrl),
    hostAuth: () => _navidrome.authParams,
    userName: () => _navidrome.username,
    playNow: (item) => _partyDj.playNow(item),
    radioEnabled: () => _partyDj.radioEnabled,
    setRadioEnabled: (enabled) => _partyDj.radioEnabled = enabled,
    saveRecap: savePartyRecap,
    shareRecap: _sharePartyRecap,
    packPlaylists: () => [
      for (final playlist in playlists)
        if (playlist.ownerUsername == null && playlist.trackIds.isNotEmpty)
          (
            id: playlist.id,
            name: playlist.name,
            tracks: playlist.trackIds
                .map(_findTrackById)
                .whereType<Track>()
                .toList(),
          ),
    ],
    isOffline: areTracksOffline,
    downloadOffline: (tracks, onProgress) =>
        downloadTracksOffline(tracks, onProgress: onProgress),
    blindTest: blindTestHost,
  );

  /// Blind test de la soiree, joue sur le lecteur de l'hote.
  late final BlindTestHost blindTestHost = BlindTestHost(
    relay: party,
    playback: _PlayerBlindTestPlayback(_player),
    library: () => allTracks,
    setDjSuspended: (suspended) => _partyDj.suspended = suspended,
  );
  bool get isPersonalSyncParticipant => _jamCtl.isPersonalSyncParticipant;
  bool get isPersonalSyncHost => _jamCtl.isPersonalSyncHost;
  bool get isFriendJamActive => _jamCtl.isFriendJamActive;
  Track? get remoteTrack => _jamCtl.remoteTrack;
  String? get remoteDeviceName => _jamCtl.remoteDeviceName;
  String? get connectedParticipantDeviceName =>
      _jamCtl.connectedParticipantDeviceName;
  Future<String?> startJamSession() => _jamCtl.startSession();
  Future<bool> joinJamSession(String sessionId) =>
      _jamCtl.joinSession(sessionId);
  void transferJamHost(String targetUsername) =>
      _jamCtl.transferHost(targetUsername);
  Future<void> leaveJamSession() => _jamCtl.leaveSession();
  Future<void> takeOverPersonalSync() => _jamCtl.takeOverPersonalSync();

  Timer? _nowPlayingHeartbeat;

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

  /// Fondu enchaine et normalisation (Parametres > Lecture).
  final PlaybackSettings playbackSettings = PlaybackSettings();

  /// Decalage audio de cet appareil en Jam (menu Jam).
  final JamSyncSettings jamSyncSettings = JamSyncSettings();
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
  @override
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
  @override
  List<Album> get albums => _music.albums;
  MusicService get musicService => _music;

  /// Ecoutes du compte sur cet appareil, pour le bilan (voir ListeningLog).
  Future<List<PlayEvent>> listeningHistory() => _music.listeningHistory();
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
  void _refreshHomeShelves() {
    _homeShelves = HomeShelves.compute(allTracks, albums);
    _smartPlaylists = SmartPlaylist.compute(allTracks);
  }

  /// Playlists intelligentes de l'accueil (voir SmartPlaylist), recalculees
  /// avec les etageres.
  List<SmartPlaylist> _smartPlaylists = const [];
  List<SmartPlaylist> get smartPlaylists => _smartPlaylists;

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

  /// Les services sont crees une seule fois dans main.dart et fournis aussi
  /// aux widgets par `provider` (voir VinlandApp).
  AppState({
    required VinlandAudioHandler audioHandler,
    required MusicService music,
    required NavidromeService navidrome,
    required JamService jamService,
    PartyController? party,
    DiscoveryService? discovery,
  })  : _audioHandler = audioHandler,
        _music = music,
        _navidrome = navidrome {
    _player = PlayerController(
      output: audioHandler,
      tracks: _tracks,
      settings: playbackSettings,
    )
      ..onTrackLoading = ((track) => _theme.updateCoverColor(track.coverPath))
      ..onPlayingChanged = _syncNowPlayingMirror
      ..onTrackStarted = _onTrackStarted;
    _jamCtl = JamController(
      jam: jamService,
      playback: _player,
      tracks: _tracks,
      username: () => _navidrome.username,
      deviceLabel: _deviceLabel,
      personalSyncIds: _personalSyncIds,
      syncSettings: jamSyncSettings,
    )..onHostingChanged = _syncNowPlayingMirror;
    _player.onEngineEvent = _jamCtl.broadcastState;
    // Un participant qui suit un hote change de titre quand l'hote le dit,
    // jamais en avance par un fondu (voir PlayerController.allowCrossfade).
    _player.allowCrossfade = () => !_jamCtl.isActive || _jamCtl.isHost;
    this.party = party ??
        PartyController(
          connect: WebSocketPartySocket.connect,
          store: PrefsPartySeatStore(),
          recapStore: PrefsPartyRecapStore(),
        );
    _partyDj = PartyHostDj(
      this.party,
      PlayerPartyPlayback(
        player: _player,
        playTrack: playTrack,
        findTrack: _findTrackById,
      ),
      radio: _radio = PartyRadio([
        NavidromeRadioSource(_navidrome.similarSongs),
        if (discovery != null)
          RelatedArtistsRadioSource(
            relatedArtists: (artist) => _relatedArtists(discovery, artist),
            library: () => allTracks,
          ),
        SameArtistRadioSource(() => allTracks),
      ]),
    );
    this.party.addListener(_partyDj.sync);
    _player.addListener(_notify);
    _jamCtl.addListener(_notify);
    _theme.addListener(_notify);
    _navigator.addListener(_notify);

    _audioHandler.browser = VinlandMediaBrowser(
      likedTracks: () => likedTracks,
      weeklyTracks: () => homeWeeklyTracks,
      allTracks: () => allTracks,
      playlists: () => [
        for (final p in playlists)
          if (p.trackIds.isNotEmpty)
            (
              id: p.id,
              title: p.name,
              tracks:
                  p.trackIds.map(_findTrackById).whereType<Track>().toList(),
            ),
      ],
      newAlbums: () => [
        for (final a in homeNewOnServerAlbums)
          (
            id: a.id,
            title: '${a.title} · ${a.artist}',
            tracks: a.trackIds.map(_findTrackById).whereType<Track>().toList(),
          ),
      ],
      currentTrack: () => currentTrack,
      play: (track, list) => playTrack(track, trackList: list),
      search: _music.searchTracks,
    );
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

  /// Artistes proches de [artist] selon Deezer (radio du mode Soiree).
  static Future<List<String>> _relatedArtists(
      DiscoveryService discovery, String artist) async {
    final found = await discovery.searchArtists(artist, limit: 3);
    for (final candidate in found) {
      if (MatchingService.artistsMatch(candidate.name, artist)) {
        return discovery.getRelatedArtistNames(candidate.id);
      }
    }
    return const [];
  }

  /// Recap du mode Soiree : une playlist avec tout ce qui a ete joue, et
  /// qui l'a propose en description. Renvoie l'id local de la playlist.
  Future<String?> savePartyRecap(String name, List<PartyPlayed> played) async {
    try {
      final id = await _music.createPlaylist(name);
      for (final entry in played) {
        await _music.addToPlaylist(id, 'navidrome_${entry.song.songId}');
      }
      final serverId =
          playlists.where((pl) => pl.id == id).firstOrNull?.serverId;
      final comment = partyRecapComment(played);
      if (serverId != null && comment.isNotEmpty) {
        await _navidrome.setPlaylistMeta(serverId, comment: comment);
      }
      _notify();
      return id;
    } catch (e) {
      debugPrint('savePartyRecap error: $e');
      return null;
    }
  }

  Future<void> _sharePartyRecap(BuildContext context, String playlistId) async {
    final playlist = playlists.where((pl) => pl.id == playlistId).firstOrNull;
    if (playlist == null) return;
    if (shareInboxConfigured) {
      await showSendToFriendDialog(
        context,
        type: 'playlist',
        title: playlist.name,
        subtitle: 'Recap de soirée',
        playlistForPrivacyCheck: playlist,
      );
    } else {
      await sharePlaylist(context, playlist);
    }
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
    // JamController.onLocalTrackStarted) tant qu'aucune session Jam entre
    // amis manuelle n'est en cours -- diffuse aussi l'etat si deja hote.
    unawaited(_jamCtl.onLocalTrackStarted());
    final partySong = partySongForTrack(track);
    if (partySong != null) _partyDj.onTrackStarted(partySong);
    if (_cast?.isCasting ?? false) unawaited(_sendCastExtras(track));
  }

  /// Paroles et couleur de la pochette pour l'ecran tele (recepteur
  /// Chromecast de Vinland). Les paroles arrivent du reseau : le temps
  /// qu'elles arrivent, la couleur de la pochette est en general calculee.
  Future<void> _sendCastExtras(Track track) async {
    Lyrics? found;
    try {
      found = await lyrics.lyricsFor(track);
    } catch (e) {
      debugPrint('Paroles pour la Chromecast: $e');
    }
    if (currentTrack?.id != track.id) return;
    _cast?.sendExtras(
      accent: castAccentHex(dominantColor),
      lyrics: castLyricLines(found),
    );
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
      await playbackSettings.load(prefs);
      await jamSyncSettings.load(prefs);
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
      _jamCtl.startPersonalSyncPolling();
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
      // Retour au premier plan : un autre appareil du compte joue peut-etre
      // deja, on reprend un sondage rapproche (voir startPersonalSyncPolling).
      if (!isJamActive && _navidrome.username != null) {
        _jamCtl.startPersonalSyncPolling();
      }
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
  @override
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

  /// Retourne false si GitHub a refuse la verification (limite de requetes
  /// atteinte) : updateInfo vient alors du dernier resultat connu.
  /// [force] : clic explicite de l'utilisateur, ignore l'intervalle d'une
  /// heure entre deux verifications (voir UpdateCheckService).
  Future<bool> checkForUpdate({bool force = false}) async {
    final result = await UpdateCheckService().checkForUpdate(force: force);
    updateInfo = result.info;
    if (updateInfo != null) _notify();
    return !result.rateLimited;
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _notifyDebounce?.cancel();
    _nowPlayingHeartbeat?.cancel();
    _jamCtl.dispose();
    _cast?.dispose();
    party.dispose();
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
    await _cast?.disconnect();
    await _player.stopOutput();
    // Voir JamController.disconnect : la session Jam ne doit pas survivre a
    // la deconnexion du compte.
    unawaited(_jamCtl.disconnect());
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
  @override
  Future<void> playTrack(Track track, {List<Track>? trackList}) async {
    // Participant de Jam ou de synchro perso : voir
    // JamController.interceptPlayTrack.
    if (_jamCtl.interceptPlayTrack(track)) return;
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
    if (_jamCtl.interceptTogglePlayPause()) return;
    // Redemarrage de l'app (aucune source chargee) : PlayerController
    // relance une vraie lecture du dernier titre, sans rien diffuser ici.
    if (_player.togglePlayPause()) _jamCtl.broadcastState();
  }

  Future<void> nextTrack() async {
    if (_jamCtl.interceptNext()) return;
    await _player.next();
  }

  /// Avant 3s de lecture : revient au titre precedent (file d'attente
  /// remise en tete). Au-dela : redemarre simplement le titre en cours,
  /// comme la plupart des lecteurs.
  Future<void> previousTrack() async {
    if (_jamCtl.interceptPrevious()) return;
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
    _jamCtl.relayAddToQueue(track);
    _player.addToQueue(track);
  }

  /// "Lire ensuite" (options d'un titre) : le place en tete de `queue`, donc
  /// juste apres le titre en cours -- contrairement a addToQueue qui l'ajoute
  /// a la fin. Pour mettre plusieurs titres en file en une fois (ex: un album
  /// entier), appeler dans l'ordre inverse voulu (le dernier insere en tete
  /// se retrouve premier). Meme relais vers l'hote qu'addToQueue en
  /// participant de Jam.
  void playNext(Track track) {
    _jamCtl.relayPlayNext(track);
    _player.playNext(track);
  }

  void removeFromQueue(int index) => _player.removeFromQueue(index);

  /// Reordonnancement par glisser-deposer (voir QueueScreen) : `newIndex`
  /// suit la convention de ReorderableListView.onReorder (index cible avant
  /// le retrait de l'element deplace).
  void reorderQueue(int oldIndex, int newIndex) =>
      _player.reorderQueue(oldIndex, newIndex);

  void seek(Duration pos) {
    if (_jamCtl.interceptSeek(pos)) return;
    _player.seek(pos);
  }

  /// Ce qui doit s'afficher dans la barre de lecture (mini-player, plein
  /// ecran, barre desktop) : le titre/etat local normalement, mais celui de
  /// l'hote quand on est un participant de synchro perso (voir
  /// isPersonalSyncParticipant) -- rien ne joue localement dans ce cas, donc
  /// currentTrack/isPlaying/position locaux seraient perimes ou vides.
  Track? get displayTrack =>
      isPersonalSyncParticipant ? _jamCtl.remoteTrack : currentTrack;
  bool get displayIsPlaying =>
      isPersonalSyncParticipant ? _jamCtl.remoteIsPlaying : isPlaying;
  Duration get displayPosition => isPersonalSyncParticipant
      ? (_jamCtl.remotePosition ?? Duration.zero)
      : position;

  Track? _findTrackById(String id) => _tracks.findById(id);

  /// « Lancer la radio » : joue [seed] puis des titres proches de la
  /// bibliotheque (memes sources que la radio du mode Soiree). False si
  /// rien de proche n'a ete trouve.
  Future<bool> startRadio(Track seed) async {
    final song = partySongForTrack(seed);
    if (song == null) return false;
    final tracks = (await _radio.mix(song))
        .map((s) => _findTrackById('navidrome_${s.songId}'))
        .whereType<Track>()
        .toList();
    if (tracks.isEmpty) return false;
    await playTrack(seed, trackList: [seed, ...tracks]);
    return true;
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

  bool get needsSharingConsent => _music.needsSharingConsent;

  Future<void> confirmSharingConsent({
    required bool likes,
    required bool recentPlays,
    required bool nowPlaying,
  }) async {
    await _music.confirmSharingConsent(
      likes: likes,
      recentPlays: recentPlays,
      nowPlaying: nowPlaying,
    );
    _notify();
  }

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

  @override
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
      unawaited(_jamCtl.disconnect());
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
  @override
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

/// Extrait de blind test sur le vrai lecteur : le titre, puis un saut au
/// moment choisi (le refrain plutot que l'intro).
class _PlayerBlindTestPlayback implements BlindTestPlayback {
  _PlayerBlindTestPlayback(this._player);
  final PlayerController _player;

  @override
  Future<void> playExtract(Track track, Duration from) async {
    await _player.playTrack(track);
    if (from > Duration.zero) _player.seek(from);
  }
}
