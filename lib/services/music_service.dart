import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:metadata_god/metadata_god.dart';
import '../data/cache/library_cache.dart';
import '../data/subsonic/subsonic_exception.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../models/friend_profile.dart';
import '../models/pinned_item.dart';
import '../models/recent_play.dart';
import '../models/collab_playlist.dart';
import 'legacy_file_migration.dart';
import 'navidrome_service.dart';
import 'personal_sync_secret.dart';
import 'sharing_consent.dart';
import 'package:http/http.dart' as http;

/// Fusionne un titre fraichement recu du serveur (Navidrome) avec l'etat
/// local deja connu (cache) et le statut "starred" -- coeur de
/// [MusicService.syncWithNavidrome], extrait en fonction pure top-level pour
/// pouvoir etre teste sans mock HTTP (voir test/music_service_reconcile_test.dart).
/// A deja cause deux regressions distinctes sur l'ordre des "Titres likes"
/// (perte de dateAdded ecrasee a tort, puis cache local absent apres
/// reinstall) -- toute modification ici merite un test avant tout.
void reconcileTrack(
  Track t, {
  required Map<String, DateTime?> starredMap,
  required Map<String, Map<String, dynamic>> localData,
  required Set<String> tracksNeedingOrderRecovery,
}) {
  if (starredMap.containsKey(t.id)) {
    t.isLiked = true;
    t.dateAdded = starredMap[t.id] ?? t.dateAdded;
  }
  final local = localData[t.id];
  if (local != null) {
    t.isLiked = local['isLiked'] ?? t.isLiked;
    // superLiked n'a aucun equivalent cote Navidrome : purement local,
    // toujours reporte tel quel (jamais recalcule depuis le serveur).
    t.superLiked = local['superLiked'] ?? false;
    // ?? et non ecrasement direct : si le cache local n'a pas encore de
    // date (ex: track starred hors de l'app) on garde celle du serveur
    // posee juste au-dessus, plutot que de la remettre a null et casser
    // le tri de la liste "Titres likes" (voir AppState.likedTracks).
    t.dateAdded = local['dateAdded'] ?? t.dateAdded;
    t.playCount = local['playCount'] ?? t.playCount;
    t.lastPlayed = local['lastPlayed'] ?? t.lastPlayed;
  }
  // Aucune source locale fiable pour la date de ce titre like (cache
  // vide ou date jamais connue en local) : la date posee ci-dessus vient
  // du timestamp "starred" du serveur, pas garanti dans l'ordre d'import
  // d'origine (resolution grossiere, pas forcement pose dans l'ordre du
  // CSV importe). A recuperer depuis l'ordre reel de la playlist miroir
  // des likes une fois celle-ci relue -- voir _syncPlaylistsFromServer.
  if (t.isLiked && (local == null || local['dateAdded'] == null)) {
    tracksNeedingOrderRecovery.add(t.id);
  }
}

/// Resultat de [planPlaylistSync] : playlists locales deja connues dont le
/// contenu serveur doit etre rafraichi, et playlists nouvellement decouvertes
/// (creees ici, pas encore ajoutees a la liste locale par l'appelant).
class PlaylistSyncPlan {
  final List<Playlist> toRefresh;
  final List<Playlist> discovered;
  PlaylistSyncPlan(this.toRefresh, this.discovered);
}

/// Decide, pour chaque playlist du serveur appartenant a l'utilisateur
/// courant (deja filtree a "mine" par l'appelant), si elle correspond a un
/// objet [Playlist] local deja connu (a rafraichir) ou doit etre decouverte
/// (jamais vue sur CET appareil) -- coeur de
/// [MusicService._syncPlaylistsFromServer], extrait en fonction pure pour
/// etre testable sans mock HTTP (voir
/// test/music_service_playlist_sync_test.dart).
///
/// Avant l'ajout de la branche "decouverte", une playlist qui existait cote
/// serveur sous ce compte mais que l'appareil courant n'avait jamais creee
/// lui-meme (typiquement : creee pour un ami depuis un AUTRE appareil/
/// session) etait silencieusement ignoree pour toujours -- ni rafraichie
/// (pas de correspondance locale par serverId) ni republiee (elle a deja un
/// serverId, donc ignoree par la boucle "playlists locales -> serveur").
/// Vecu par l'utilisateur : playlist invisible chez le proprietaire une fois
/// connecte sur son propre appareil, alors que visible via son profil
/// (FriendProfile, qui lit directement depuis le serveur sans ce filtre).
PlaylistSyncPlan planPlaylistSync(
  List<Map<String, dynamic>> mine,
  List<Playlist> localPlaylists, {
  required Set<String?> ignoredServerIds,
  required String collabTagPrefix,
}) {
  final byServerId = {
    for (final p in localPlaylists)
      if (p.serverId != null) p.serverId!: p,
  };
  final toRefresh = <Playlist>[];
  final discovered = <Playlist>[];
  for (final pl in mine) {
    final serverId = pl['id'] as String;
    if (ignoredServerIds.contains(serverId)) continue;

    final comment = pl['comment'] as String? ?? '';
    // Sous-liste d'une playlist collaborative : mergee separement par
    // MusicService.fetchCollabPlaylist(), ne doit jamais apparaitre comme
    // une playlist normale a part entiere ici.
    if (comment.startsWith(collabTagPrefix)) continue;
    // Porteuse du secret de synchro perso (voir personal_sync_secret.dart) :
    // playlist technique et vide, jamais une vraie playlist de l'utilisateur.
    if (comment.startsWith(personalSyncTagPrefix)) continue;

    final local = byServerId[serverId];
    if (local != null) {
      local.isPublic = pl['public'] == true;
      toRefresh.add(local);
      continue;
    }
    discovered.add(Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: pl['name'] as String? ?? 'Playlist',
      serverId: serverId,
      isPublic: pl['public'] == true,
    ));
  }
  return PlaylistSyncPlan(toRefresh, discovered);
}

class MusicService {
  /// Une seule instance par processus, creee dans main.dart (ou par
  /// l'entree Bluetooth headless) puis injectee. [storageRoot] remplace les
  /// dossiers de l'app (cache, covers) dans les tests.
  MusicService(this._navidrome, {Future<Directory> Function()? storageRoot})
      : _storageRoot = storageRoot;

  final Future<Directory> Function()? _storageRoot;

  List<Track> _allTracks = [];
  List<Album> _albums = [];
  List<Playlist> _playlists = [];
  bool _initialized = false;
  String? _coversDir;
  List<Map<String, dynamic>> _missingTracks = [];
  List<Map<String, dynamic>>? _missingTracksView;
  List<Map<String, dynamic>> get missingTracks =>
      _missingTracksView ??= List.unmodifiable(_missingTracks);

  /// Marqueur stable (champ "comment" cote serveur) de la playlist qui
  /// miroite les titres likes de l'utilisateur courant : le nom affiche,
  /// lui, est modifiable et ne doit pas servir a la retrouver.
  static const String _likesMirrorTag = 'vinland:likes-mirror';

  /// Meme principe que _likesMirrorTag, pour les N derniers titres ecoutes
  /// (voir _syncRecentPlaysMirror) -- playCount/lastPlayed restent sinon
  /// purement locaux et invisibles des amis.
  static const String _recentPlaysMirrorTag = 'vinland:recent-plays';
  static const int _recentPlaysMirrorLimit = 30;

  /// Meme principe, pour le titre actuellement charge (voir
  /// _syncNowPlayingMirror). Le nom de la playlist sert exceptionnellement
  /// de charge utile (et pas seulement le comment) : "Now playing" sans rien
  /// d'ecoute en cours, ou "Jam:<sessionId>" si en plus l'utilisateur heberge
  /// une session Jam -- evite d'inventer un deuxieme mecanisme de stockage
  /// juste pour ce petit bout d'info supplementaire.
  static const String _nowPlayingMirrorTag = 'vinland:now-playing';

  /// Au-dela de cet age, le mirroir "now playing" d'un ami est ignore (ami
  /// affiche hors-ligne) plutot que pris pour argent comptant -- voir
  /// fetchFriends. Filet de securite pour les cas ou updateNowPlaying(null)
  /// n'a pas pu s'executer (app tuee, crash, reseau coupe) : AppState
  /// republie ce mirroir toutes les 60s tant qu'un titre joue (voir
  /// _touchNowPlaying), donc un ami reellement actif ne depasse jamais ce
  /// seuil.
  static const Duration _nowPlayingStaleAfter = Duration(minutes: 2);

  // Rien n'est partagé tant que l'utilisateur n'a pas répondu à l'écran de
  // consentement (voir SharingConsent) ; un cache 1.2.x garde ses choix.
  bool _shareLikesWithFriends = false;
  bool get shareLikesWithFriends => _shareLikesWithFriends;
  bool _shareRecentPlaysWithFriends = false;
  bool get shareRecentPlaysWithFriends => _shareRecentPlaysWithFriends;
  bool _shareNowPlayingWithFriends = false;
  bool get shareNowPlayingWithFriends => _shareNowPlayingWithFriends;
  bool _sharingConsentAsked = false;

  /// true quand le compte courant est chargé mais n'a encore jamais validé
  /// ses choix de partage : l'interface doit alors poser la question.
  /// Attend _initialized pour ne pas la poser avant d'avoir lu le cache (on
  /// pré-remplirait alors « rien de partagé » à un ancien utilisateur).
  bool get needsSharingConsent => _initialized && !_sharingConsentAsked;
  final Map<String, Timer> _playlistSyncDebounce = {};

  // Cache en memoire des covers existantes pour eviter les existsSync()
  final Set<String> _existingCovers = {};
  Timer? _saveDebounceTimer;

  List<Track> get allTracks => _navidromeTracks;
  // Vue en cache, invalidee uniquement quand _albums est reassigne (voir
  // _albumsView = null a chaque reaffectation) : List.unmodifiable(_albums)
  // cree sinon un NOUVEL objet a chaque appel, ce qui casse la memoisation
  // de Selector<AppState,...> (comparaison par egalite de reference) et
  // forcait TOUS les ecrans a se re-render a chaque notifyListeners(),
  // meme quand la bibliotheque n'avait pas change (ex: juste un like, un
  // changement d'onglet...).
  List<Album>? _albumsView;
  List<Album> get albums => _albumsView ??= List.unmodifiable(_albums);
  List<Playlist> get playlists => List.unmodifiable(_playlists);

  final NavidromeService _navidrome;
  List<Track> _navidromeTracks = [];
  Map<String, String> _offlineFiles = {}; // navidrome_id -> local path

  // Meme raisonnement que _albumsView ci-dessus.
  List<Track>? _navidromeTracksView;
  List<Track> get navidromeTracks =>
      _navidromeTracksView ??= List.unmodifiable(_navidromeTracks);
  bool isTrackDownloaded(String trackId) => _offlineFiles.containsKey(trackId);
  String? getOfflinePath(String trackId) => _offlineFiles[trackId];

  List<RecentPlay> _recentPlays = [];
  List<RecentPlay> get recentPlays => List.unmodifiable(_recentPlays);

  /// Etat perso par titre (like, date du like, super-like, ecoutes), tel
  /// qu'enregistre dans le fichier de donnees perso. Garde aussi les titres
  /// absents de la bibliotheque en memoire (synchro en cours, ou
  /// bibliotheque perdue) pour que la synchro suivante les retrouve :
  /// jamais vide par une synchro.
  Map<String, Map<String, dynamic>> _trackStates = {};

  /// Vrai pendant que la synchro complete remplit la bibliotheque lot par
  /// lot : une sauvegarde a ce moment n'ecrit que les donnees perso, pas une
  /// bibliotheque a moitie recue.
  bool _libraryFetchInProgress = false;

  /// Enregistre un album/playlist/artiste comme "recemment ecoute".
  /// Deplace l'entree en tete si elle existe deja au lieu de la dupliquer.
  void recordRecentPlay(RecentPlay entry) {
    _recentPlays.removeWhere((r) => r.type == entry.type && r.id == entry.id);
    _recentPlays.insert(0, entry);
    if (_recentPlays.length > 20) {
      _recentPlays = _recentPlays.sublist(0, 20);
    }
    _debouncedSave();
  }

  static const String _pinnedMirrorTagPrefix = 'vinland:pinned-tiles:';
  Timer? _pinnedMirrorDebounce;
  String? _pinnedMirrorServerId;

  List<PinnedItem> _pinnedItems = [];
  List<PinnedItem> get pinnedItems => List.unmodifiable(_pinnedItems);

  bool isPinned(PinnedItemType type, String id) =>
      _pinnedItems.any((p) => p.sameTarget(type, id));

  /// Epingle/desepingle une tuile de l'accueil (album/playlist/artiste) pour
  /// qu'elle reste toujours visible, meme sans ecoute recente. Synchronisee
  /// via le profil Navidrome (voir _syncPinnedMirror) pour retrouver les
  /// memes epingles sur un autre appareil ou sur l'app Windows (retour
  /// utilisateur).
  void togglePin(PinnedItem item) {
    final existing =
        _pinnedItems.indexWhere((p) => p.sameTarget(item.type, item.id));
    if (existing != -1) {
      _pinnedItems.removeAt(existing);
    } else {
      _pinnedItems.add(item);
    }
    _debouncedSave();
    _syncPinnedMirror();
  }

  /// Republie (avec un leger debounce) la liste complete des tuiles
  /// epinglees dans le champ "comment" d'une playlist miroir cachee -- meme
  /// mecanisme que les autres miroirs (likes, ecoutes recentes...), mais le
  /// contenu utile ici est le JSON du commentaire lui-meme (la playlist reste
  /// vide de titres) : une tuile epinglee peut etre un album/une playlist/un
  /// artiste, pas seulement des titres, donc rien a mettre dans le contenu
  /// normal d'une playlist Navidrome.
  void _syncPinnedMirror() {
    if (!_navidrome.isConnected) return;
    _pinnedMirrorDebounce?.cancel();
    _pinnedMirrorDebounce = Timer(const Duration(seconds: 2), () async {
      final comment = _pinnedMirrorTagPrefix +
          jsonEncode(_pinnedItems.map((p) => p.toJson()).toList());
      var mirrorId = _pinnedMirrorServerId;
      if (mirrorId == null) {
        // null = serveur injoignable : surtout ne pas creer de doublon.
        final existing = await _navidrome.fetchPlaylistsOrNull();
        if (existing == null) return;
        final match = existing.firstWhere(
          (pl) =>
              pl['owner'] == _navidrome.username &&
              (pl['comment'] as String? ?? '')
                  .startsWith(_pinnedMirrorTagPrefix),
          orElse: () => <String, dynamic>{},
        );
        mirrorId = match['id'] as String?;
        if (mirrorId != null) {
          _pinnedMirrorServerId = mirrorId;
          _debouncedSave();
          await _navidrome.setPlaylistMeta(mirrorId, comment: comment);
          return;
        }
        mirrorId = await _navidrome.createServerPlaylist('Vinland: epingles',
            comment: comment, public: false);
        if (mirrorId == null) return;
        _pinnedMirrorServerId = mirrorId;
        _debouncedSave();
        return;
      }
      await _navidrome.setPlaylistMeta(mirrorId, comment: comment);
    });
  }

  /// Retrouve la playlist miroir des tuiles epinglees parmi une liste de
  /// playlists deja recuperee (fetchPlaylists()) et adopte son contenu -- le
  /// JSON encode dans son "comment" fait foi, ecrase l'etat local. Appelee
  /// par la synchro complete ET la synchro legere (contrairement aux autres
  /// miroirs, purement "push") : sans ca, un pin fait sur un autre appareil
  /// ne remonterait qu'a la prochaine synchro complete, possible seulement
  /// toutes les 6h (voir AppState._performSync).
  void _applyPinnedMirrorFrom(List<Map<String, dynamic>> ownedPlaylists) {
    final match = ownedPlaylists.firstWhere(
      (pl) =>
          (pl['comment'] as String? ?? '').startsWith(_pinnedMirrorTagPrefix),
      orElse: () => <String, dynamic>{},
    );
    final id = match['id'] as String?;
    if (id == null) {
      _pinnedMirrorServerId = null;
      if (_pinnedItems.isNotEmpty) _syncPinnedMirror();
      return;
    }
    _pinnedMirrorServerId = id;
    try {
      final decoded = jsonDecode((match['comment'] as String)
          .substring(_pinnedMirrorTagPrefix.length)) as List;
      _pinnedItems = decoded
          .map((p) => PinnedItem.fromJson(Map<String, dynamic>.from(p)))
          .toList();
      _debouncedSave();
    } catch (e) {
      debugPrint('Pinned mirror decode error: $e');
    }
  }

  String? _currentUserId;

  void setCurrentUser(String? userId) {
    if (userId == _currentUserId) return;
    _currentUserId = userId;
    _resetInMemoryState();
    _initialized = false;
  }

  /// Vide tout l'etat en memoire propre a un compte avant de charger celui
  /// d'un autre (login/logout/changement de serveur -- voir
  /// AppState.configureNavidrome/logout). Sans ca, la bibliotheque, les
  /// likes et les playlists du compte precedent restaient en memoire tant
  /// qu'un rechargement de cache ne les remplaçait pas -- et si le nouveau
  /// compte n'a encore aucun fichier de cache local sur cet appareil (jamais
  /// connecte ici), rien ne les remplaçait jamais.
  ///
  /// Pire : les Timer de debounce (_debouncedSave, miroirs de
  /// likes/ecoutes-recentes/now-playing, sync de playlist) relisent l'etat
  /// au moment ou ILS SE DECLENCHENT (jusqu'a 2s plus tard), pas au moment
  /// ou ils sont programmes -- un compte A qui like un titre puis bascule
  /// sur le compte B dans les 2 secondes qui suivent pouvait donc pousser
  /// SES propres likes vers le serveur DU COMPTE B (playlist miroir), ou
  /// ecrire la bibliotheque du compte A dans le fichier de cache local du
  /// compte B. Annuler ces Timer ici (plutot que d'attendre qu'ils se
  /// declenchent avec l'ancien etat) est ce qui coupe vraiment la fuite.
  /// Observe par l'utilisateur : des titres qui "changent de compte" en
  /// changeant d'utilisateur, la playlist miroir des likes d'un ami montrant
  /// des titres qu'il n'a jamais likes lui-meme.
  void _resetInMemoryState() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    _likesMirrorDebounce?.cancel();
    _likesMirrorDebounce = null;
    _recentPlaysMirrorDebounce?.cancel();
    _recentPlaysMirrorDebounce = null;
    _nowPlayingMirrorDebounce?.cancel();
    _nowPlayingMirrorDebounce = null;
    _pinnedMirrorDebounce?.cancel();
    _pinnedMirrorDebounce = null;
    for (final timer in _playlistSyncDebounce.values) {
      timer.cancel();
    }
    _playlistSyncDebounce.clear();

    _navidromeTracks = [];
    _navidromeTracksView = null;
    _allTracks = [];
    _albums = [];
    _albumsView = null;
    _playlists = [];
    _offlineFiles = {};
    _missingTracks = [];
    _missingTracksView = null;
    _recentPlays = [];
    _trackStates = {};
    _pinnedItems = [];
    _existingCovers.clear();
    _tracksNeedingOrderRecovery.clear();

    _shareLikesWithFriends = false;
    _likesMirrorServerId = null;
    _shareRecentPlaysWithFriends = false;
    _recentPlaysMirrorServerId = null;
    _shareNowPlayingWithFriends = false;
    _nowPlayingMirrorServerId = null;
    _sharingConsentAsked = false;
    _pinnedMirrorServerId = null;
  }

  String get _cacheFileName => 'library$_accountSuffix.json';
  String get _userDataFileName => 'userdata$_accountSuffix.json';
  String get _accountSuffix =>
      (_currentUserId != null && _currentUserId!.isNotEmpty)
          ? '_$_currentUserId'
          : '';

  Future<void> initialize() async {
    if (_initialized) return;
    _coversDir = await _getCoversDir();

    await _loadFromCache();
    await _refreshCoverCache();
    _initialized = true;
  }

  Future<String> _getCoversDir() async {
    final appDir = await (_storageRoot ?? getApplicationDocumentsDirectory)();
    final dir = Directory(p.join(appDir.path, 'covers'));
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Rafraichit le cache des covers existantes (appele une fois au demarrage)
  Future<void> _refreshCoverCache() async {
    _existingCovers.clear();
    if (_coversDir == null) return;
    final dir = Directory(_coversDir!);
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File) _existingCovers.add(entity.path);
    }
  }

  /// Verifie si une cover existe (utilise le cache, pas de I/O synchrone)
  bool coverExists(String? path) {
    if (path == null) return false;
    if (path.startsWith('http')) return true;
    return _existingCovers.contains(path);
  }

  Future<String?> _saveCover(Uint8List bytes, String trackId) async {
    if (_coversDir == null) return null;
    try {
      final ext = _detectImageFormat(bytes);
      final filePath = p.join(_coversDir!, '${trackId.hashCode}.$ext');
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      _existingCovers.add(filePath);
      return filePath;
    } catch (e) {
      debugPrint('ERREUR SAUVEGARDE COVER: $e');
      return null;
    }
  }

  String _detectImageFormat(Uint8List bytes) {
    if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg';
    if (bytes.length > 8 && bytes[0] == 0x89) return 'png';
    return 'jpg';
  }

  Future<void> scanDirectory(String dirPath) async {
    final normalizedPath = dirPath.replaceAll(r'\\', r'\');
    final dir = Directory(normalizedPath);

    if (!await dir.exists()) {
      debugPrint('DOSSIER NON TROUVE: $normalizedPath');
      return;
    }

    final List<Track> scanned = [];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (['.mp3', '.flac', '.m4a', '.ogg', '.wav'].contains(ext)) {
          final track = await parseFile(entity.path);
          scanned.add(track);
        }
      }
    }

    if (scanned.isNotEmpty) {
      _allTracks = scanned;
      rebuildAlbums();
      _debouncedSave();
    }
  }

  String _normalizeTitle(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void rebuildAlbums() {
    // Préserver les albums existants par ID (isSaved, artist)
    final existingAlbums = <String, Album>{};
    for (final a in _albums) {
      existingAlbums[a.id] = a;
    }

    // Groupe par albumId Navidrome quand il existe (identifiant reel et
    // unique cote serveur), et seulement par titre pour les titres qui n'en
    // ont pas (locaux/importes). Grouper par titre seul (comme avant)
    // fusionnait a tort deux albums differents partageant le meme titre --
    // ex: une reedition/deluxe et un tout autre album d'un autre artiste --
    // en un seul, avec les titres de l'un ajoutes a la fin de l'autre
    // (retour utilisateur : des titres d'un autre artiste apparaissaient en
    // fin de liste d'un album).
    final Map<String, List<Track>> albumMap = {};
    for (final track in _navidromeTracks) {
      final key = track.albumId ?? track.album;
      albumMap.putIfAbsent(key, () => []).add(track);
    }

    final newAlbums = <Album>[];
    for (final entry in albumMap.entries) {
      // Deduplique par titre normalise (garde la version likee si le NAS a
      // le meme morceau range plusieurs fois dans cet album) : sinon
      // trackIds/le nombre de titres comptent des doublons partout en aval
      // (page album, "Decouverte" qui classe a tort un album comme single...).
      final byTitle = <String, Track>{};
      for (final t in entry.value) {
        final key = _normalizeTitle(t.title);
        final existing = byTitle[key];
        if (existing == null || (!existing.isLiked && t.isLiked)) {
          byTitle[key] = t;
        }
      }
      final tracks = byTitle.values.toList();
      String? albumCover;
      for (final track in tracks) {
        if (track.coverPath != null) {
          albumCover = track.coverPath;
          break;
        }
      }

      final firstTrack = tracks.first;
      final navidromeId = firstTrack.albumId;
      final id = navidromeId != null
          ? 'navidrome_$navidromeId'
          : entry.key.hashCode.toString();

      // Préserver l'artiste et isSaved de l'album existant
      final existing = existingAlbums[id];
      final artist =
          firstTrack.albumArtist ?? existing?.artist ?? firstTrack.artist;

      final year = firstTrack.year ?? existing?.year;

      DateTime? addedToServerAt = existing?.addedToServerAt;
      for (final t in tracks) {
        final added = t.addedToServerAt;
        if (added != null &&
            (addedToServerAt == null || added.isAfter(addedToServerAt))) {
          addedToServerAt = added;
        }
      }

      newAlbums.add(Album(
        id: id,
        title: firstTrack.album,
        artist: artist,
        trackIds: tracks.map((t) => t.id).toList(),
        isSaved: existing?.isSaved ?? false,
        coverPath: albumCover,
        year: year,
        addedToServerAt: addedToServerAt,
      ));
    }

    _albums = newAlbums;
    _albumsView = null;
  }

  Future<Track> parseFile(String filePath) async {
    final fileName = p.basenameWithoutExtension(filePath);
    final albumDir = p.basename(p.dirname(filePath));
    final artistDir = p.basename(p.dirname(p.dirname(filePath)));

    String title = fileName;
    String artist = artistDir;
    String album = albumDir;
    String? coverPath;
    Duration duration = const Duration(minutes: 3);

    try {
      final metadata = await MetadataGod.readMetadata(file: filePath);

      title = metadata.title ?? _extractTitleFromFileName(fileName);
      artist = metadata.artist ?? artistDir;
      album = metadata.album ?? albumDir;

      if (metadata.picture != null) {
        coverPath = await _saveCover(metadata.picture!.data, filePath);
      }

      if (metadata.durationMs != null && metadata.durationMs! > 0) {
        duration = Duration(milliseconds: metadata.durationMs!.toInt());
      }
    } catch (e) {
      debugPrint('ERREUR METADATA: $filePath - $e');
      title = _extractTitleFromFileName(fileName);
    }

    return Track(
      id: filePath,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      filePath: filePath,
      coverPath: coverPath,
    );
  }

  String _extractTitleFromFileName(String fileName) {
    String title = fileName;
    final numberMatch = RegExp(r'^\d+\.\s*').firstMatch(fileName);
    if (numberMatch != null) {
      title = fileName.substring(numberMatch.end).trim();
    }
    return title;
  }

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

  List<Track> get likedTracks {
    final liked = _allTracks.where((t) => t.isLiked).toList();
    liked.sort((a, b) {
      final da = a.dateAdded ?? DateTime(2000);
      final db = b.dateAdded ?? DateTime(2000);
      if (da == db) {
        return _allTracks.indexOf(a).compareTo(_allTracks.indexOf(b));
      }
      return db.compareTo(da);
    });
    return liked;
  }

  List<Album> get likedAlbums => _albums.where((a) => a.isSaved).toList();

  Future<void> toggleLikeAlbum(String albumId) async {
    final album = _albums.firstWhere(
      (a) => a.id == albumId,
      orElse: () => throw Exception('Album $albumId not found'),
    );
    album.isSaved = !album.isSaved;

    if (album.id.startsWith('navidrome_')) {
      final cleanId = album.id.replaceFirst('navidrome_', '');
      if (album.isSaved) {
        await _navidrome.starAlbum(cleanId);
      } else {
        await _navidrome.unstarAlbum(cleanId);
      }
    }
    _debouncedSave();
  }

  Future toggleLike(String trackId) async {
    final track = _allTracks.firstWhere(
      (t) => t.id == trackId,
      orElse: () => throw Exception('Track $trackId not found'),
    );
    track.isLiked = !track.isLiked;
    if (!track.isLiked) {
      // Un titre super-like est toujours aussi like : le retirer des titres
      // likes doit aussi lui retirer son super-like.
      track.superLiked = false;
    } else {
      // Toujours (pas seulement si dateAdded etait encore null) : un
      // relike doit remonter le titre en tete de la liste "Titres likes",
      // pas le remettre a sa position d'avant l'unlike (retour utilisateur).
      track.dateAdded = DateTime.now();
    }
    if (track.id.startsWith('navidrome_')) {
      if (track.isLiked) {
        await _navidrome.starTrack(track.id);
      } else {
        await _navidrome.unstarTrack(track.id);
      }
    }
    _debouncedSave();
    _syncLikesMirror();
  }

  /// Variante visuelle du like normal (coeur double) : implique isLiked,
  /// mais purement locale, sans equivalent Navidrome (voir Track.superLiked).
  /// Un appui long desactive le super-like sans retirer le like normal.
  Future<void> toggleSuperLike(String trackId) async {
    final track = _allTracks.firstWhere(
      (t) => t.id == trackId,
      orElse: () => throw Exception('Track $trackId not found'),
    );
    track.superLiked = !track.superLiked;
    if (track.superLiked && !track.isLiked) {
      track.isLiked = true;
      // Meme raison que toggleLike : un titre qu'on relike doit remonter
      // en tete de la liste, pas garder son ancienne date.
      track.dateAdded = DateTime.now();
      if (track.id.startsWith('navidrome_')) {
        await _navidrome.starTrack(track.id);
      }
    }
    _debouncedSave();
    _syncLikesMirror();
  }

  Timer? _likesMirrorDebounce;
  String? _likesMirrorServerId;

  /// Ids des titres likes dont la date d'ajout locale etait manquante lors
  /// du dernier syncWithNavidrome (cache vide -- reinstall, deconnexion,
  /// etc.) : reconcile() leur pose alors la date "starred" du serveur en
  /// repli, grossiere et pas garantie dans l'ordre d'import d'origine.
  /// _syncPlaylistsFromServer() la remplace par une date synthetique derivee
  /// de l'ordre reel (fiable, lui) de la playlist miroir des likes des
  /// qu'elle est recuperee -- voir le commentaire complet la-bas.
  final Set<String> _tracksNeedingOrderRecovery = {};

  /// Enregistre la réponse à l'écran de consentement et applique chaque
  /// choix (visibilité des playlists miroirs sur le serveur).
  Future<void> confirmSharingConsent({
    required bool likes,
    required bool recentPlays,
    required bool nowPlaying,
  }) async {
    _sharingConsentAsked = true;
    await setShareLikesWithFriends(likes);
    await setShareRecentPlaysWithFriends(recentPlays);
    await setShareNowPlayingWithFriends(nowPlaying);
    await saveToCache();
  }

  Future<void> setShareLikesWithFriends(bool value) async {
    _shareLikesWithFriends = value;
    _debouncedSave();
    if (_likesMirrorServerId != null) {
      await _navidrome.setPlaylistMeta(_likesMirrorServerId!, public: value);
    } else {
      _syncLikesMirror();
    }
  }

  /// Maintient une playlist serveur ("miroir") a jour avec les titres likes
  /// de l'utilisateur courant, pour que les amis puissent la voir si elle
  /// est publique. Debounce : evite un aller-retour reseau a chaque like
  /// quand l'utilisateur en enchaine plusieurs d'un coup.
  void _syncLikesMirror() {
    if (!_navidrome.isConnected) return;
    _likesMirrorDebounce?.cancel();
    _likesMirrorDebounce = Timer(const Duration(seconds: 3), () async {
      var mirrorId = _likesMirrorServerId;
      if (mirrorId == null) {
        // null = serveur injoignable : surtout ne pas creer de doublon.
        final existing = await _navidrome.fetchPlaylistsOrNull();
        if (existing == null) return;
        final mine = existing.firstWhere(
          (pl) =>
              pl['owner'] == _navidrome.username &&
              pl['comment'] == _likesMirrorTag,
          orElse: () => <String, dynamic>{},
        );
        mirrorId = mine['id'] as String?;
        mirrorId ??= await _navidrome.createServerPlaylist(
          'Titres likes',
          comment: _likesMirrorTag,
          public: _shareLikesWithFriends,
        );
        if (mirrorId == null) return;
        _likesMirrorServerId = mirrorId;
        _debouncedSave();
      }
      final cleanIds =
          likedTracks.map((t) => t.id.replaceFirst('navidrome_', '')).toList();
      await _navidrome.replacePlaylistSongs(mirrorId, cleanIds);
    });
  }

  Timer? _recentPlaysMirrorDebounce;
  String? _recentPlaysMirrorServerId;

  Future<void> setShareRecentPlaysWithFriends(bool value) async {
    _shareRecentPlaysWithFriends = value;
    _debouncedSave();
    if (_recentPlaysMirrorServerId != null) {
      await _navidrome.setPlaylistMeta(_recentPlaysMirrorServerId!,
          public: value);
    } else {
      _syncRecentPlaysMirror();
    }
  }

  /// Meme mecanisme que _syncLikesMirror, pour les _recentPlaysMirrorLimit
  /// derniers titres ecoutes (tries par lastPlayed decroissant).
  void _syncRecentPlaysMirror() {
    if (!_navidrome.isConnected) return;
    _recentPlaysMirrorDebounce?.cancel();
    _recentPlaysMirrorDebounce = Timer(const Duration(seconds: 3), () async {
      var mirrorId = _recentPlaysMirrorServerId;
      if (mirrorId == null) {
        // null = serveur injoignable : surtout ne pas creer de doublon.
        final existing = await _navidrome.fetchPlaylistsOrNull();
        if (existing == null) return;
        final mine = existing.firstWhere(
          (pl) =>
              pl['owner'] == _navidrome.username &&
              pl['comment'] == _recentPlaysMirrorTag,
          orElse: () => <String, dynamic>{},
        );
        mirrorId = mine['id'] as String?;
        mirrorId ??= await _navidrome.createServerPlaylist(
          'Écouté récemment',
          comment: _recentPlaysMirrorTag,
          public: _shareRecentPlaysWithFriends,
        );
        if (mirrorId == null) return;
        _recentPlaysMirrorServerId = mirrorId;
        _debouncedSave();
      }
      final recent = _allTracks.where((t) => t.lastPlayed != null).toList()
        ..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));
      final cleanIds = recent
          .take(_recentPlaysMirrorLimit)
          .map((t) => t.id.replaceFirst('navidrome_', ''))
          .toList();
      await _navidrome.replacePlaylistSongs(mirrorId, cleanIds);
    });
  }

  Timer? _nowPlayingMirrorDebounce;
  String? _nowPlayingMirrorServerId;

  Future<void> setShareNowPlayingWithFriends(bool value) async {
    _shareNowPlayingWithFriends = value;
    _debouncedSave();
    if (_nowPlayingMirrorServerId != null) {
      await _navidrome.setPlaylistMeta(_nowPlayingMirrorServerId!,
          public: value);
    }
  }

  /// Republie (avec un leger debounce) le titre actuellement charge, pour
  /// qu'il apparaisse dans l'onglet Amis des autres comptes -- voir
  /// AppState, qui appelle ceci a chaque changement de titre et de session
  /// Jam. `jamSessionId` non-null si l'utilisateur heberge une session Jam
  /// en ce moment : permet aux amis de la rejoindre en un tap plutot que de
  /// devoir se faire passer/coller un code.
  void updateNowPlaying(String? trackId, {String? jamSessionId}) {
    if (!_navidrome.isConnected) return;
    _nowPlayingMirrorDebounce?.cancel();
    _nowPlayingMirrorDebounce =
        Timer(const Duration(milliseconds: 800), () async {
      final name = jamSessionId != null ? 'Jam:$jamSessionId' : 'Now playing';
      var mirrorId = _nowPlayingMirrorServerId;
      if (mirrorId == null) {
        // null = serveur injoignable : surtout ne pas creer de doublon.
        final existing = await _navidrome.fetchPlaylistsOrNull();
        if (existing == null) return;
        final mine = existing.firstWhere(
          (pl) =>
              pl['owner'] == _navidrome.username &&
              pl['comment'] == _nowPlayingMirrorTag,
          orElse: () => <String, dynamic>{},
        );
        mirrorId = mine['id'] as String?;
        mirrorId ??= await _navidrome.createServerPlaylist(
          name,
          comment: _nowPlayingMirrorTag,
          public: _shareNowPlayingWithFriends,
        );
        if (mirrorId == null) return;
        _nowPlayingMirrorServerId = mirrorId;
        _debouncedSave();
      }
      await _navidrome.setPlaylistMeta(mirrorId, name: name);
      final cleanIds = trackId == null
          ? <String>[]
          : [trackId.replaceFirst('navidrome_', '')];
      await _navidrome.replacePlaylistSongs(mirrorId, cleanIds);
    });
  }

  Future<String> createPlaylist(String name) async {
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
    );
    _playlists.add(playlist);
    _debouncedSave();
    if (_navidrome.isConnected) {
      playlist.serverId = await _navidrome.createServerPlaylist(name);
      _debouncedSave();
    }
    return playlist.id;
  }

  Future<void> addToPlaylist(String playlistId, String trackId) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    if (!playlist.trackIds.contains(trackId)) {
      playlist.trackIds.add(trackId);
      _debouncedSave();
      _syncPlaylistToServer(playlist);
    }
  }

  Future<void> removeFromPlaylist(String playlistId, String trackId) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    playlist.trackIds.remove(trackId);
    _debouncedSave();
    _syncPlaylistToServer(playlist);
  }

  Future<void> deletePlaylist(String playlistId) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    _playlists.removeWhere((p) => p.id == playlistId);
    _debouncedSave();
    _playlistSyncDebounce.remove(playlistId)?.cancel();
    if (playlist.serverId != null) {
      await _navidrome.deleteServerPlaylist(playlist.serverId!);
    }
  }

  Future<void> setPlaylistPublic(String playlistId, bool public) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    playlist.isPublic = public;
    _debouncedSave();
    if (playlist.serverId != null) {
      await _navidrome.setPlaylistMeta(playlist.serverId!, public: public);
    }
  }

  static const String _collabTagPrefix = 'vinland:collab:';

  String? _commentFor(Playlist playlist) => playlist.collabGroupId != null
      ? '$_collabTagPrefix${playlist.collabGroupId}'
      : null;

  /// Genere un identifiant aleatoire non devinable pour grouper les
  /// sous-listes d'une playlist collaborative -- meme esprit que le salt
  /// Subsonic (voir NavidromeService._generateSalt).
  String _generateGroupId() {
    final random = Random.secure();
    final bytes = List.generate(9, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Cree une playlist collaborative : chaque participant garde sa propre
  /// sous-liste (une playlist Navidrome par personne -- l'API Subsonic
  /// n'autorise pas l'edition d'une playlist par quelqu'un d'autre que son
  /// proprietaire), regroupees via collabGroupId (stocke cote serveur dans
  /// le champ "comment", comme les playlists-miroirs). Renvoie le groupId a
  /// partager avec les amis, ou null si la creation serveur a echoue.
  Future<String?> createCollabPlaylist(String name) async {
    if (!_navidrome.isConnected) return null;
    final groupId = _generateGroupId();
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      isPublic: true,
      collabGroupId: groupId,
    );
    playlist.serverId = await _navidrome.createServerPlaylist(
      name,
      comment: _commentFor(playlist),
      public: true,
    );
    if (playlist.serverId == null) return null;
    _playlists.add(playlist);
    _debouncedSave();
    return groupId;
  }

  /// Rejoint une playlist collaborative existante : cree sa propre
  /// sous-liste (vide au depart) taguee du meme groupId.
  Future<bool> joinCollabPlaylist(String groupId, String name) async {
    if (!_navidrome.isConnected) return false;
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      isPublic: true,
      collabGroupId: groupId,
    );
    playlist.serverId = await _navidrome.createServerPlaylist(
      name,
      comment: _commentFor(playlist),
      public: true,
    );
    if (playlist.serverId == null) return false;
    _playlists.add(playlist);
    _debouncedSave();
    return true;
  }

  /// Fusionne toutes les sous-listes (la sienne + celles des amis) qui
  /// partagent ce groupId : titres dedupliques (premiere occurrence
  /// rencontree conservee) avec qui a ajoute chacun.
  Future<CollabPlaylistView> fetchCollabPlaylist(String groupId) async {
    final tag = '$_collabTagPrefix$groupId';
    final raw = await _navidrome.fetchPlaylists();
    final matches = raw.where((pl) => pl['comment'] == tag).toList();

    final addedBy = <String, String>{};
    final order = <String>[];
    String? name;
    for (final pl in matches) {
      name ??= pl['name'] as String?;
      final owner = pl['owner'] as String;
      final trackIds =
          await _navidrome.fetchPlaylistSongIds(pl['id'] as String);
      for (final id in trackIds) {
        final fullId = 'navidrome_$id';
        if (!addedBy.containsKey(fullId)) {
          addedBy[fullId] = owner;
          order.add(fullId);
        }
      }
    }
    return CollabPlaylistView(
      groupId: groupId,
      name: name ?? 'Playlist collaborative',
      trackIds: order,
      addedBy: addedBy,
    );
  }

  /// Renvoie sur le serveur le contenu complet d'une playlist locale, avec
  /// un debounce par playlist : evite un aller-retour reseau a chaque ajout
  /// quand l'utilisateur enchaine plusieurs titres d'un coup.
  void _syncPlaylistToServer(Playlist playlist) {
    if (!_navidrome.isConnected) return;
    _playlistSyncDebounce[playlist.id]?.cancel();
    _playlistSyncDebounce[playlist.id] =
        Timer(const Duration(seconds: 2), () async {
      var serverId = playlist.serverId;
      if (serverId == null) {
        serverId = await _navidrome.createServerPlaylist(playlist.name,
            comment: _commentFor(playlist), public: playlist.isPublic);
        if (serverId == null) return;
        playlist.serverId = serverId;
        _debouncedSave();
      }
      final cleanIds = playlist.trackIds
          .map((id) => id.replaceFirst('navidrome_', ''))
          .toList();
      await _navidrome.replacePlaylistSongs(serverId, cleanIds);
    });
  }

  Future<void> recordPlay(String trackId) async {
    // Peut ne rien trouver si la lecture demarre pendant une synchro encore
    // en cours (le titre existe deja dans la file mais _allTracks n'a pas
    // encore atteint son lot) -- rien a compter dans ce cas.
    Track? track;
    for (final t in _allTracks) {
      if (t.id == trackId) {
        track = t;
        break;
      }
    }
    if (track == null) return;
    track.playCount++;
    track.lastPlayed = DateTime.now();
    _debouncedSave();
    _syncRecentPlaysMirror();
  }

  /// Le cache vit dans le dossier support de l'app (AppData\Roaming sous
  /// Windows, dossier prive sous Android) et plus dans Documents, que
  /// Windows synchronise souvent avec OneDrive : ces fichiers n'ont rien a
  /// faire dans le cloud de l'utilisateur. La bibliotheque va dans cache/,
  /// les donnees perso dans userdata/ (voir LibraryCacheStore).
  ///
  /// Les noms de fichiers sont lus AVANT tout await : un changement de
  /// compte pendant la recherche du dossier ne doit pas faire ecrire les
  /// donnees d'un compte dans les fichiers d'un autre.
  Future<LibraryCacheStore> _cacheStore() {
    final libraryName = _cacheFileName;
    final userDataName = _userDataFileName;
    return _cacheStoreFor(libraryName, userDataName);
  }

  Future<LibraryCacheStore> _cacheStoreFor(
      String libraryName, String userDataName) async {
    final root = await (_storageRoot ?? getApplicationSupportDirectory)();
    final libraryPath = p.join(root.path, 'cache', libraryName);
    if (_storageRoot == null) await _migrateLegacyCacheFile(File(libraryPath));
    return LibraryCacheStore(
      libraryPath: libraryPath,
      userDataPath: p.join(root.path, 'userdata', userDataName),
    );
  }

  /// Migration unique depuis Documents/cache (<= 1.2.x) : deplace l'ancien
  /// fichier s'il n'existe pas encore de cache au nouvel endroit, puis
  /// supprime l'ancien dans tous les cas (il contenait des URL avec jeton,
  /// voir SubsonicRefs). Le contenu est assaini au premier chargement
  /// (Track.fromJson) puis reecrit sans URL tout de suite apres.
  Future<void> _migrateLegacyCacheFile(File target) async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final legacy =
          File(p.join(documentsDir.path, 'cache', p.basename(target.path)));
      await migrateLegacyFile(legacy: legacy, target: target);
    } catch (e) {
      debugPrint('MIGRATION CACHE: $e');
    }
  }

  /// Reporte l'etat perso des titres en memoire dans [_trackStates]. Les
  /// titres absents de la bibliotheque en memoire gardent leur etat.
  void _captureTrackStates() {
    for (final t in _navidromeTracks) {
      final state = trackUserStateOf(t);
      if (state == null) {
        _trackStates.remove(t.id);
      } else {
        _trackStates[t.id] = state;
      }
    }
  }

  Map<String, dynamic> _userDataJson() {
    _captureTrackStates();
    return {
      'offlineFiles': Map<String, String>.from(_offlineFiles),
      'missingTracks': _missingTracks,
      'recentPlays': _recentPlays.map((r) => r.toJson()).toList(),
      'playlists': _playlists.map((pl) => pl.toJson()).toList(),
      'pinnedItems': _pinnedItems.map((p) => p.toJson()).toList(),
      'shareLikesWithFriends': _shareLikesWithFriends,
      'likesMirrorServerId': _likesMirrorServerId,
      'shareRecentPlaysWithFriends': _shareRecentPlaysWithFriends,
      'recentPlaysMirrorServerId': _recentPlaysMirrorServerId,
      'shareNowPlayingWithFriends': _shareNowPlayingWithFriends,
      'nowPlayingMirrorServerId': _nowPlayingMirrorServerId,
      'sharingConsentAsked': _sharingConsentAsked,
      'pinnedMirrorServerId': _pinnedMirrorServerId,
      'trackStates': Map<String, dynamic>.from(_trackStates),
    };
  }

  Map<String, dynamic> _libraryJson() => {
        'navidromeTracks': _navidromeTracks
            .map((t) => withoutTrackUserFields(t.toJson()))
            .toList(),
        'albums': _albums.map((a) => a.toJson()).toList(),
      };

  Future _saveToCache() async {
    // Contenu fige tout de suite (avant le premier await), comme les noms
    // de fichiers dans _cacheStore.
    final userData = _userDataJson();
    final library = _libraryFetchInProgress ? null : _libraryJson();
    final store = _cacheStore();
    try {
      await (await store).save(userData: userData, library: library);
    } catch (e) {
      // Le fichier precedent est intact (ecriture atomique) : on log et la
      // prochaine sauvegarde reessaiera.
      debugPrint('ERREUR SAUVEGARDE CACHE: $e');
    }
  }

  void addTrack(Track track) {
    if (!_allTracks.any((t) => t.id == track.id)) {
      _allTracks.add(track);
    }
  }

  Future<void> saveToCache() async {
    _saveDebounceTimer?.cancel();
    await _saveToCache();
  }

  Future _loadFromCache() async {
    final LoadedCache loaded;
    try {
      loaded = await (await _cacheStore()).load();
    } catch (e) {
      debugPrint('ERREUR CHARGEMENT CACHE: $e');
      return;
    }
    debugPrint('CACHE: bibliotheque ${loaded.libraryBytes ~/ 1024} Ko, '
        'donnees perso ${loaded.userDataBytes ~/ 1024} Ko');

    final user = loaded.userData;
    if (user != null) {
      try {
        _applyUserData(user);
      } catch (e) {
        debugPrint('ERREUR LECTURE DONNEES PERSO: $e');
      }
    }
    final library = loaded.library;
    if (library != null) {
      try {
        _applyLibrary(library, hasUserData: user != null);
      } catch (e) {
        debugPrint('ERREUR LECTURE BIBLIOTHEQUE: $e');
      }
    }

    // Migration de schema, version precedente rechargee, ou cache d'avant
    // la 1.3 (URL avec jeton, deja converties en references a la lecture,
    // voir SubsonicRefs) : reecrit tout de suite plutot qu'a la prochaine
    // synchro, pour que le disque soit sain des le premier lancement.
    if (loaded.needsRewrite) await _saveToCache();
  }

  void _applyUserData(Map<String, dynamic> data) {
    _offlineFiles = Map<String, String>.from(data['offlineFiles'] ?? {});
    _playlists = (data['playlists'] as List?)
            ?.map((pl) => Playlist.fromJson(Map<String, dynamic>.from(pl)))
            .toList() ??
        [];
    final consent = SharingConsent.fromCache(data);
    _shareLikesWithFriends = consent.likes;
    _likesMirrorServerId = data['likesMirrorServerId'];
    _shareRecentPlaysWithFriends = consent.recentPlays;
    _recentPlaysMirrorServerId = data['recentPlaysMirrorServerId'];
    _shareNowPlayingWithFriends = consent.nowPlaying;
    _sharingConsentAsked = consent.asked;
    _nowPlayingMirrorServerId = data['nowPlayingMirrorServerId'];
    _missingTracks = (data['missingTracks'] as List?)
            ?.map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        [];
    _missingTracksView = null;
    _recentPlays = (data['recentPlays'] as List?)
            ?.map((r) => RecentPlay.fromJson(Map<String, dynamic>.from(r)))
            .toList() ??
        [];
    _pinnedItems = (data['pinnedItems'] as List?)
            ?.map((p) => PinnedItem.fromJson(Map<String, dynamic>.from(p)))
            .toList() ??
        [];
    _pinnedMirrorServerId = data['pinnedMirrorServerId'];
    _trackStates = {
      for (final e in ((data['trackStates'] as Map?) ?? const {}).entries)
        if (e.value is Map)
          e.key.toString(): Map<String, dynamic>.from(e.value as Map),
    };
  }

  void _applyLibrary(Map<String, dynamic> data, {required bool hasUserData}) {
    _navidromeTracks = (data['navidromeTracks'] as List?)
            ?.map((json) => Track.fromJson(Map<String, dynamic>.from(json)))
            .toList() ??
        [];
    // Le fichier de donnees perso fait foi pour les likes et compteurs. S'il
    // est perdu (lui et sa version precedente), les likes reviendront du
    // serveur a la prochaine synchro (voir reconcileTrack).
    if (hasUserData) {
      for (final t in _navidromeTracks) {
        applyTrackUserState(t, _trackStates[t.id]);
      }
    }
    _navidromeTracksView = null;
    _allTracks = List.from(_navidromeTracks);
    _albums = (data['albums'] as List?)
            ?.map((json) => Album.fromJson(Map<String, dynamic>.from(json)))
            .toList() ??
        [];
    _albumsView = null;

    // Ne rebuild que si pas d'albums en cache (premier chargement)
    if (_albums.isEmpty) {
      rebuildAlbums();
    }
  }

  Future<void> rescanCoversForExistingTracks() async {
    // Fichiers locaux uniquement : un titre Navidrome n'a pas de tags a
    // relire ici (et son "chemin" est une URL avec jeton).
    final localTracks = _allTracks
        .where((t) => t.subsonicId == null && t.filePath != null)
        .toList();

    int updated = 0;
    for (final track in localTracks) {
      if (track.coverPath != null) {
        final file = File(track.coverPath!);
        if (await file.exists()) continue;
      }

      try {
        final metadata = await MetadataGod.readMetadata(file: track.filePath!);
        if (metadata.picture != null) {
          final coverPath =
              await _saveCover(metadata.picture!.data, track.filePath!);
          if (coverPath != null) {
            final index = _allTracks.indexWhere((t) => t.id == track.id);
            if (index != -1) {
              _allTracks[index] = Track(
                id: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration,
                filePath: track.filePath,
                coverPath: coverPath,
                isLiked: track.isLiked,
                playCount: track.playCount,
                lastPlayed: track.lastPlayed,
                albumId: track.albumId,
                albumArtist: track.albumArtist,
                year: track.year,
                addedToServerAt: track.addedToServerAt,
                genre: track.genre,
                trackNumber: track.trackNumber,
                discNumber: track.discNumber,
                replayGain: track.replayGain,
              );
              updated++;
            }
          }
        }
      } catch (e) {
        // L'id plutot que le chemin : jamais d'URL (jeton) dans les logs.
        debugPrint('ERREUR COVER ${track.id}: $e');
      }
    }

    if (updated > 0) {
      rebuildAlbums();
      _debouncedSave();
    }
    debugPrint('RESCAN COVERS: $updated covers ajoutees');
  }

  void _debouncedSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(seconds: 2), () async {
      await _saveToCache();
    });
  }

  /// [onProgress] est appele a chaque page de titres recue pendant la
  /// synchro (voir NavidromeService.fetchAllTracks) : la bibliotheque
  /// affichee (allTracks/albums) se remplit donc progressivement au lieu de
  /// rester figee sur l'ancien cache jusqu'a la toute fin d'une resynchro
  /// complete, qui peut prendre du temps sur une grosse bibliotheque.
  ///
  /// Renvoie false si la synchro a echoue en cours de route : la
  /// bibliotheque d'avant est alors remise en place, au lieu d'enregistrer
  /// une bibliotheque tronquee a la premiere page en erreur.
  Future<bool> syncWithNavidrome({void Function()? onProgress}) async {
    debugPrint('SYNC NAVIDROME...');
    _tracksNeedingOrderRecovery.clear();
    // Recuperes avant les titres (requetes uniques, rapides) pour pouvoir
    // reconcilier chaque lot de titres avec son statut like/date des son
    // arrivee, plutot qu'en une seule passe finale sur toute la liste.
    final starredMap =
        await _navidrome.fetchStarredTrackIds(); // Map<String, DateTime?>
    final starredAlbumIds = await _navidrome.fetchStarredAlbumIds();

    // Etat perso enregistre d'abord (couvre les titres absents de la
    // bibliotheque en memoire, ex. cache de bibliotheque perdu), puis celui
    // des titres en memoire, plus recent.
    final localData = <String, Map<String, dynamic>>{
      for (final e in _trackStates.entries)
        e.key: trackUserStateForReconcile(e.value),
    };
    for (final t in _navidromeTracks) {
      localData[t.id] = {
        'isLiked': t.isLiked,
        'superLiked': t.superLiked,
        'dateAdded': t.dateAdded,
        'playCount': t.playCount,
        'lastPlayed': t.lastPlayed,
      };
    }

    void reconcile(Track t) => reconcileTrack(
          t,
          starredMap: starredMap,
          localData: localData,
          tracksNeedingOrderRecovery: _tracksNeedingOrderRecovery,
        );

    void applyAlbumStarred() {
      for (final album in _albums) {
        album.isSaved = starredAlbumIds.contains(album.id);
      }
    }

    final previousTracks = _navidromeTracks;
    // Chaque lot recu remplace sa version en cache, sans retirer le reste :
    // repartir de zero rendait toute la bibliotheque pas encore re-recue
    // invisible et injouable le temps de la synchro (retour utilisateur :
    // "faire le plus important d'abord, mes sons"). Les titres disparus du
    // NAS ne partent qu'a la fin, avec la liste complete.
    final merged = {for (final t in previousTracks) t.id: t};
    final List<Track> fresh;
    // Les titres en memoire vont etre remplaces lot par lot : leur etat perso
    // est mis de cote avant, pour qu'une sauvegarde pendant la synchro ne
    // perde rien de ce qui n'a pas encore ete re-recu.
    _captureTrackStates();
    _libraryFetchInProgress = true;
    try {
      fresh = await _navidrome.fetchAllTracks(onBatch: (batch) {
        for (final t in batch) {
          reconcile(t);
          merged[t.id] = t;
        }
        _navidromeTracks = merged.values.toList();
        _navidromeTracksView = null;
        _allTracks = List.from(_navidromeTracks);
        rebuildAlbums();
        applyAlbumStarred();
        onProgress?.call();
      });
    } on SubsonicException catch (e) {
      debugPrint('SYNC NAVIDROME interrompue, bibliotheque conservee: $e');
      _navidromeTracks = previousTracks;
      _navidromeTracksView = null;
      _allTracks = List.from(_navidromeTracks);
      rebuildAlbums();
      applyAlbumStarred();
      onProgress?.call();
      return false;
    } finally {
      _libraryFetchInProgress = false;
    }

    _navidromeTracks = fresh;
    _navidromeTracksView = null;
    _allTracks = List.from(_navidromeTracks);
    rebuildAlbums();
    applyAlbumStarred();

    _debouncedSave();
    debugPrint('SYNC NAVIDROME: ${_navidromeTracks.length} tracks');

    await _syncPlaylistsFromServer();
    return true;
  }

  /// Recupere juste les quelques albums les plus recents (un aller-retour
  /// HTTP rapide) et les fusionne dans la bibliotheque locale, au lieu de
  /// relancer syncWithNavidrome() en entier : une synchro complete reconstruit
  /// _navidromeTracks lot par lot en partant de zero, ce qui rend
  /// temporairement injouable tout titre pas encore re-recu -- inadapte pour
  /// simplement faire apparaitre UN morceau tout juste telecharge (voir la
  /// fonctionnalite de telechargement automatique dans discovered_album_screen).
  /// Retourne le nombre de titres effectivement ajoutes/mis a jour.
  Future<int> syncRecentlyAdded({int albumCount = 5}) async {
    final recentAlbums = await _navidrome.fetchRecentAlbums(count: albumCount);
    if (recentAlbums.isEmpty) return 0;

    final fetchedLists = await Future.wait(recentAlbums.map((album) =>
        _navidrome.fetchAlbumTracks(album['id'] as String,
            albumArtist: album['artist']?.toString())));

    final byId = {for (final t in _navidromeTracks) t.id: t};
    var changed = 0;
    for (final tracks in fetchedLists) {
      for (final t in tracks) {
        final existing = byId[t.id];
        if (existing != null) {
          // Conserve les donnees purement locales (likes, compteurs) que ce
          // fetch cible n'a pas -- contrairement a syncWithNavidrome(), on ne
          // rappelle pas fetchStarredTrackIds ici pour rester rapide.
          t.isLiked = existing.isLiked;
          t.superLiked = existing.superLiked;
          t.dateAdded = existing.dateAdded;
          t.playCount = existing.playCount;
          t.lastPlayed = existing.lastPlayed;
        }
        byId[t.id] = t;
        changed++;
      }
    }
    if (changed == 0) return 0;

    _navidromeTracks = byId.values.toList();
    _navidromeTracksView = null;
    _allTracks = List.from(_navidromeTracks);
    rebuildAlbums();
    _debouncedSave();
    return changed;
  }

  /// Filet de securite pour un telechargement dont le resultat peut echapper
  /// a syncRecentlyAdded (voir NavidromeService.findTrack) -- appele EN PLUS,
  /// pas a la place : syncRecentlyAdded reste la voie normale et reste
  /// necessaire pour rafraichir le reste de l'album/artiste autour.
  Future<bool> findAndAdoptTrack(String artist, String title) async {
    final track = await _navidrome.findTrack(artist, title);
    if (track == null) return false;
    final existingIndex = _navidromeTracks.indexWhere((t) => t.id == track.id);
    if (existingIndex != -1) {
      final existing = _navidromeTracks[existingIndex];
      track.isLiked = existing.isLiked;
      track.superLiked = existing.superLiked;
      track.dateAdded = existing.dateAdded;
      track.playCount = existing.playCount;
      track.lastPlayed = existing.lastPlayed;
      _navidromeTracks[existingIndex] = track;
    } else {
      _navidromeTracks.add(track);
    }
    _navidromeTracksView = null;
    _allTracks = List.from(_navidromeTracks);
    rebuildAlbums();
    _debouncedSave();
    return true;
  }

  /// Synchro "legere" utilisee a chaque ouverture de l'app quand une synchro
  /// complete (syncWithNavidrome) a deja ete faite recemment (voir
  /// AppState._performSync) : pas de refetch de toute la bibliotheque, juste
  /// les likes serveur pas encore connus localement + les derniers albums
  /// ajoutes (syncRecentlyAdded), pour une ouverture rapide sans re-tirer
  /// des milliers de titres a chaque fois.
  ///
  /// Ne retire jamais un like/album sauvegarde localement meme si le
  /// serveur ne le voit plus starred (contrairement a syncWithNavidrome) :
  /// seule une synchro complete peut retirer un like local. Ca evite de
  /// pouvoir re-effacer des likes tout juste faits (import CSV notamment)
  /// si cette synchro legere tombe pendant l'import.
  Future<void> lightSync() async {
    debugPrint('LIGHT SYNC (pas de refetch complet)...');
    final starredTracks = await _navidrome.fetchStarredTracks();
    final starredMap = {for (final t in starredTracks) t.id: t.dateAdded};
    final starredAlbumIds = await _navidrome.fetchStarredAlbumIds();

    // Contrairement aux likes/albums ci-dessous, les tuiles epinglees sont
    // adoptees ici aussi (pas seulement dans la synchro complete) : sinon un
    // pin fait sur un autre appareil/l'app Windows ne remonterait qu'a la
    // prochaine synchro complete, possible seulement toutes les 6h.
    final username = _navidrome.username;
    if (username != null) {
      final ownedPlaylists = (await _navidrome.fetchPlaylists())
          .where((pl) => pl['owner'] == username)
          .toList();
      _applyPinnedMirrorFrom(ownedPlaylists);
      // Nettoyage d'une eventuelle decouverte erronee d'avant ce correctif
      // (voir le meme removeWhere dans _syncPlaylistsFromServer) : fait ici
      // aussi pour que ça disparaisse des le prochain lancement plutot que
      // d'attendre la prochaine synchro complete (jusqu'a 6h).
      if (_pinnedMirrorServerId != null) {
        _playlists.removeWhere((p) => p.serverId == _pinnedMirrorServerId);
      }
    }

    // Derniers ajouts AVANT d'appliquer les likes : un titre tout juste
    // arrive sur le NAS et like depuis un autre appareil ressortait sinon
    // de syncRecentlyAdded sans son like.
    await syncRecentlyAdded();

    var changed = false;
    for (final t in _allTracks) {
      if (!t.isLiked && starredMap.containsKey(t.id)) {
        t.isLiked = true;
        t.dateAdded = starredMap[t.id] ?? t.dateAdded;
        changed = true;
      }
    }
    // Like fait ailleurs (ex: app PC) sur un titre que cet appareil ne
    // connait pas encore -- sinon invisible jusqu'a la prochaine synchro
    // complete (6h).
    final knownIds = {for (final t in _navidromeTracks) t.id};
    final unknown =
        starredTracks.where((t) => !knownIds.contains(t.id)).toList();
    if (unknown.isNotEmpty) {
      _navidromeTracks.addAll(unknown);
      _navidromeTracksView = null;
      _allTracks = List.from(_navidromeTracks);
      rebuildAlbums();
      changed = true;
    }
    for (final album in _albums) {
      if (!album.isSaved && starredAlbumIds.contains(album.id)) {
        album.isSaved = true;
        changed = true;
      }
    }

    if (changed) _debouncedSave();
  }

  /// Fait correspondre les playlists locales avec celles du serveur : publie
  /// celles qui n'existaient encore que localement (cree avant cette
  /// synchro), et recupere l'etat (id serveur, contenu, public) des autres.
  /// Repere aussi la playlist miroir des likes par son "comment" et
  /// synchronise son contenu si elle n'est pas encore a jour.
  Future<void> _syncPlaylistsFromServer() async {
    if (!_navidrome.isConnected) return;
    final username = _navidrome.username;
    if (username == null) return;

    // null = serveur injoignable : sans la liste du serveur, on republierait
    // en double les playlists locales.
    final raw = await _navidrome.fetchPlaylistsOrNull();
    if (raw == null) return;
    final mine = raw.where((pl) => pl['owner'] == username).toList();

    // Playlists creees en local avant d'avoir jamais synchronise : on les
    // publie maintenant sur le serveur.
    for (final playlist in _playlists) {
      if (playlist.serverId != null ||
          playlist.isLikesMirror ||
          playlist.isRecentPlaysMirror) {
        continue;
      }
      final serverId = await _navidrome.createServerPlaylist(playlist.name,
          comment: _commentFor(playlist), public: playlist.isPublic);
      if (serverId == null) continue;
      playlist.serverId = serverId;
      final cleanIds = playlist.trackIds
          .map((id) => id.replaceFirst('navidrome_', ''))
          .toList();
      await _navidrome.replacePlaylistSongs(serverId, cleanIds);
    }

    // Retrouve/cree la playlist miroir des likes.
    final mirrorRaw = mine.firstWhere(
      (pl) => pl['comment'] == _likesMirrorTag,
      orElse: () => <String, dynamic>{},
    );
    _likesMirrorServerId = mirrorRaw['id'] as String?;
    if (_likesMirrorServerId == null) {
      _syncLikesMirror();
    } else if (_tracksNeedingOrderRecovery.isNotEmpty) {
      await _recoverLikesOrderFromMirror();
    }

    // Retrouve/cree la playlist miroir des ecoutes recentes.
    final recentMirrorRaw = mine.firstWhere(
      (pl) => pl['comment'] == _recentPlaysMirrorTag,
      orElse: () => <String, dynamic>{},
    );
    _recentPlaysMirrorServerId = recentMirrorRaw['id'] as String?;
    if (_recentPlaysMirrorServerId == null) {
      _syncRecentPlaysMirror();
    }

    // Retrouve/adopte la playlist miroir des tuiles epinglees.
    _applyPinnedMirrorFrom(mine);
    // ignoredServerIds ci-dessous (voir planPlaylistSync) ne faisait pas
    // encore cette exclusion avant ce correctif : une install deja touchee
    // a donc pu decouvrir cette playlist miroir comme une playlist normale
    // et vide ("Vinland: epingles", retour utilisateur) -- on la retire ici
    // si elle trainait deja en local, en plus de ne plus la (re)decouvrir.
    if (_pinnedMirrorServerId != null) {
      _playlists.removeWhere((p) => p.serverId == _pinnedMirrorServerId);
    }

    // Retrouve la playlist miroir "en ecoute" si elle existe deja -- pas de
    // creation eager ici (contrairement aux deux precedentes) : rien a y
    // publier tant qu'aucune lecture n'a demarre, updateNowPlaying() la
    // cree a la volee au premier appel sinon.
    final nowPlayingRaw = mine.firstWhere(
      (pl) => pl['comment'] == _nowPlayingMirrorTag,
      orElse: () => <String, dynamic>{},
    );
    _nowPlayingMirrorServerId = nowPlayingRaw['id'] as String?;

    // Recupere le contenu serveur des playlists qui ont deja un serverId
    // (ordre/contenu peut avoir change depuis un autre appareil).
    // Decide quelles playlists rafraichir/decouvrir (pur, voir
    // planPlaylistSync) puis va chercher le contenu serveur (I/O) de
    // chacune -- l'ordre/contenu peut avoir change depuis un autre appareil,
    // et une playlist "decouverte" n'a encore aucun trackIds local.
    final plan = planPlaylistSync(
      mine,
      _playlists,
      ignoredServerIds: {
        _likesMirrorServerId,
        _recentPlaysMirrorServerId,
        _nowPlayingMirrorServerId,
        _pinnedMirrorServerId,
      },
      collabTagPrefix: _collabTagPrefix,
    );
    _playlists.addAll(plan.discovered);
    for (final playlist in [...plan.toRefresh, ...plan.discovered]) {
      playlist.trackIds
        ..clear()
        ..addAll(await _navidrome.fetchPlaylistSongIds(playlist.serverId!));
    }

    _debouncedSave();
  }

  /// Reconstitue la date d'ajout des titres likes listes dans
  /// [_tracksNeedingOrderRecovery] (dont le cache local n'avait pas de date
  /// fiable -- reinstall, deconnexion, etc.) a partir de l'ORDRE REEL de la
  /// playlist miroir des likes sur le serveur, plutot que du timestamp
  /// "starred" pose en repli par reconcile() (grossier, pas garanti dans
  /// l'ordre d'import CSV d'origine). La playlist miroir est justement
  /// reecrite dans le bon ordre a chaque like/unlike (voir _syncLikesMirror),
  /// donc son contenu survit a n'importe quelle perte de cache local --
  /// c'est la meme "sauvegarde de l'ordre sur le profil" que celle deja
  /// utilisee pour que les amis voient les titres likes dans le bon ordre.
  /// Dates synthetiques (pas les vraies dates d'ajout, perdues avec le
  /// cache) : seul l'ordre relatif compte pour le tri de "Titres likes".
  Future<void> _recoverLikesOrderFromMirror() async {
    final mirrorId = _likesMirrorServerId;
    if (mirrorId == null) return;
    final orderedIds = await _navidrome.fetchPlaylistSongIds(mirrorId);
    if (orderedIds.isEmpty) return;

    final byId = {for (final t in _navidromeTracks) t.id: t};
    final base = DateTime.now();
    var recovered = 0;
    for (var i = 0; i < orderedIds.length; i++) {
      final id = orderedIds[i];
      if (!_tracksNeedingOrderRecovery.contains(id)) continue;
      final track = byId[id];
      if (track == null) continue;
      track.dateAdded = base.subtract(Duration(seconds: i));
      recovered++;
    }
    _tracksNeedingOrderRecovery.clear();
    if (recovered > 0) {
      debugPrint(
          'ORDRE TITRES LIKES: $recovered date(s) recuperee(s) depuis la playlist miroir');
      _debouncedSave();
    }
  }

  /// Amis = tout autre utilisateur du serveur ayant au moins une playlist
  /// publique (celle des likes ou une autre). Pas de systeme de
  /// demande/acceptation : tout compte cree sur ce Navidrome est considere
  /// comme un ami.
  Future<List<FriendProfile>> fetchFriends() async {
    if (!_navidrome.isConnected) return [];
    final username = _navidrome.username;
    final raw = await _navidrome.fetchPlaylists();
    final others =
        raw.where((pl) => pl['owner'] != username && pl['public'] == true);

    final byOwner = <String, List<Map<String, dynamic>>>{};
    for (final pl in others) {
      byOwner.putIfAbsent(pl['owner'] as String, () => []).add(pl);
    }

    final profiles = <FriendProfile>[];
    for (final entry in byOwner.entries) {
      final owner = entry.key;
      Playlist? likes;
      Playlist? recentPlays;
      String? nowPlayingTrackId;
      String? jamSessionId;
      final playlists = <Playlist>[];
      for (final pl in entry.value) {
        final isLikesMirror = pl['comment'] == _likesMirrorTag;
        final isRecentPlaysMirror = pl['comment'] == _recentPlaysMirrorTag;
        final isNowPlayingMirror = pl['comment'] == _nowPlayingMirrorTag;

        if (isNowPlayingMirror) {
          final changedAt = DateTime.tryParse(pl['changed'] as String? ?? '');
          final isStale = changedAt == null ||
              DateTime.now().toUtc().difference(changedAt.toUtc()) >
                  _nowPlayingStaleAfter;
          if (!isStale) {
            final trackIds =
                await _navidrome.fetchPlaylistSongIds(pl['id'] as String);
            nowPlayingTrackId = trackIds.isNotEmpty ? trackIds.first : null;
            final name = pl['name'] as String? ?? '';
            jamSessionId = name.startsWith('Jam:') ? name.substring(4) : null;
          }
          continue;
        }

        final trackIds =
            await _navidrome.fetchPlaylistSongIds(pl['id'] as String);
        final built = Playlist(
          id: pl['id'] as String,
          name: pl['name'] as String,
          trackIds: trackIds,
          serverId: pl['id'] as String,
          isPublic: true,
          ownerUsername: owner,
          isLikesMirror: isLikesMirror,
          isRecentPlaysMirror: isRecentPlaysMirror,
        );
        if (isLikesMirror) {
          likes = built;
        } else if (isRecentPlaysMirror) {
          recentPlays = built;
        } else {
          playlists.add(built);
        }
      }
      profiles.add(FriendProfile(
        username: owner,
        likesPlaylist: likes,
        recentPlaysPlaylist: recentPlays,
        playlists: playlists,
        nowPlayingTrackId: nowPlayingTrackId,
        jamSessionId: jamSessionId,
      ));
    }
    profiles.sort((a, b) => a.username.compareTo(b.username));
    return profiles;
  }

  /// Bitrate cible pour les telechargements hors-ligne : le NAS transcode a
  /// la volee, ce qui divise par ~5-10 la taille stockee sur le telephone
  /// par rapport a la qualite d'origine (FLAC/320kbps).
  static const int offlineMaxBitRateKbps = 192;

  Future<void> downloadTrack(Track track) async {
    if (!track.id.startsWith('navidrome_')) return;
    if (isTrackDownloaded(track.id)) return;

    final navidromeId = track.id.replaceFirst('navidrome_', '');
    final url = _navidrome.getStreamUrl(
      navidromeId,
      maxBitRateKbps: offlineMaxBitRateKbps,
      format: 'mp3',
    );

    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(minutes: 2));
      if (response.statusCode == 200) {
        final appDir = await getApplicationDocumentsDirectory();
        final offlineDir = Directory('${appDir.path}/offline_music');
        await offlineDir.create(recursive: true);

        final filePath = '${offlineDir.path}/${track.id.hashCode}.mp3';
        await File(filePath).writeAsBytes(response.bodyBytes);

        _offlineFiles[track.id] = filePath;
        _debouncedSave();
        debugPrint('DOWNLOADED: ${track.title} -> $filePath');
      }
    } catch (e) {
      debugPrint('DOWNLOAD ERROR ${track.title}: $e');
    }
  }

  bool areAllDownloaded(List<Track> tracks) =>
      tracks.isNotEmpty && tracks.every((t) => isTrackDownloaded(t.id));

  /// Telecharge une liste de titres (album/playlist) sequentiellement,
  /// en notifiant la progression (0.0 a 1.0) apres chaque titre.
  Future<void> downloadTracks(
    List<Track> tracks, {
    void Function(double progress)? onProgress,
  }) async {
    var done = 0;
    for (final track in tracks) {
      await downloadTrack(track);
      done++;
      onProgress?.call(done / tracks.length);
    }
  }

  Future<void> removeDownloads(List<Track> tracks) async {
    for (final track in tracks) {
      final path = _offlineFiles[track.id];
      if (path == null) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('REMOVE DOWNLOAD ERROR ${track.title}: $e');
      }
      _offlineFiles.remove(track.id);
    }
    _debouncedSave();
  }

  void setMissingTracks(List<Map<String, dynamic>> tracks) {
    _missingTracks = tracks;
    _missingTracksView = null;
    _debouncedSave();
  }

  /// Ajoute des titres manquants en ignorant les doublons (meme
  /// titre/artiste/album deja present), sans toucher a ceux deja
  /// enregistres par un import precedent.
  void addMissingTracks(List<Map<String, dynamic>> tracks) {
    for (final t in tracks) {
      final exists = _missingTracks.any((m) =>
          m['title'] == t['title'] &&
          m['artist'] == t['artist'] &&
          m['album'] == t['album']);
      if (!exists) _missingTracks.add(t);
    }
    _missingTracksView = null;
    _debouncedSave();
  }

  void clearMissingTracks() {
    _missingTracks = [];
    _missingTracksView = null;
    _debouncedSave();
  }

  /// Associe un titre "manquant" (importe via CSV, jamais retrouve
  /// automatiquement sur le NAS -- voir StreamingMatchScreen._likeMatched)
  /// a un vrai titre de la bibliotheque, choisi manuellement par
  /// l'utilisateur ou propose apres un telechargement automatique (voir
  /// MissingTracksScreen). Reprend la date synthetique posee sur l'entree
  /// manquante pour que le titre garde sa place dans l'ordre d'import une
  /// fois bascule dans les vrais titres likes (voir MusicService.likedTracks).
  Future<void> resolveMissingTrack(
      Map<String, dynamic> entry, String trackId) async {
    final track = _allTracks.firstWhere(
      (t) => t.id == trackId,
      orElse: () => throw Exception('Track $trackId not found'),
    );
    final importDate = DateTime.tryParse((entry['dateAdded'] ?? '').toString());
    track.isLiked = true;
    track.dateAdded = importDate ?? track.dateAdded ?? DateTime.now();
    if (track.id.startsWith('navidrome_')) {
      await _navidrome.starTrack(track.id);
    }
    _missingTracks.remove(entry);
    _missingTracksView = null;
    await saveToCache();
  }

  Future<void> clearAllLikes() async {
    for (final track in _allTracks) {
      track.isLiked = false;
      track.dateAdded = null;
    }
    _debouncedSave();
  }
}
