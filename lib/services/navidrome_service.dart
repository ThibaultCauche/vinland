import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import '../data/subsonic/subsonic_client.dart';
import '../data/subsonic/subsonic_exception.dart';
import '../data/subsonic/subsonic_mappers.dart';
import '../models/track.dart';
import 'matching_service.dart';
import 'cleartext_policy.dart';
import 'secure_storage.dart';
import 'subsonic_refs.dart';
import '../config/credentials.dart';

/// Facade de session au-dessus de [SubsonicClient] : identifiants, jeton,
/// URL de lecture/pochette, et conversion des reponses en modeles de l'app.
/// Les appels eux-memes (et leurs erreurs) sont dans lib/data/subsonic/.
///
/// Une seule instance par processus, creee dans main.dart (ou par l'entree
/// Bluetooth headless) puis injectee : dans AppState, MusicService et
/// WebSocketJamService, et fournie aux widgets par `provider`. Les tests
/// construisent la leur avec [NavidromeService.withClient].
class NavidromeService {
  /// Instance de l'app : branche aussi SubsonicRefs sur ses URL.
  NavidromeService() : this.withClient(SubsonicClient(), registerRefs: true);

  NavidromeService.withClient(this._client, {bool registerRefs = false}) {
    if (registerRefs) {
      // Les modeles (Track, Album...) ne stockent que des references sans
      // jeton : c'est ce service qui les transforme en URL a l'affichage.
      SubsonicRefs.streamUrlBuilder = getStreamUrl;
      SubsonicRefs.rawStreamUrlBuilder =
          (id) => getStreamUrl(id, format: 'raw');
      SubsonicRefs.coverUrlBuilder = getCoverUrl;
    }
  }

  final SubsonicClient _client;

  /// Nombre de requetes HTTP envoyees depuis le lancement.
  int get requestCount => _client.requestCount;

  String? _baseUrl;
  String? _username;
  String? _password;
  String? _token;
  String? _salt;
  // Jeton calcule localement des que les identifiants sont charges, AVANT
  // la confirmation du serveur (_token) : sert a construire les URL de
  // stream/pochette des le demarrage, comme le faisaient avant les URL
  // figees dans le cache. Nouveau sel a chaque chargement (voir _newSession).
  String? _sessionToken;
  // Cle d'API OpenSubsonic optionnelle (voir setApiKey) : quand elle est
  // definie, elle remplace u/t/s dans toutes les URL.
  String? _apiKey;

  bool get isConnected => _token != null && _baseUrl != null;

  /// Vrai des qu'un identifiant a ete charge/sauvegarde, meme si le dernier
  /// ping en direct a echoue (NAS temporairement injoignable). Sert a
  /// "rester connecte" : on ne renvoie pas l'utilisateur sur l'ecran de
  /// connexion juste parce que le reseau est momentanement capricieux.
  bool get hasCredentials =>
      (_baseUrl?.isNotEmpty ?? false) &&
      (_username?.isNotEmpty ?? false) &&
      (_password?.isNotEmpty ?? false);

  String? get baseUrl => _baseUrl;
  String? get username => _username;

  /// Un slash final dans l'URL produit une double barre dans les appels
  /// REST ('$_baseUrl/rest/...') : Navidrome redirige alors ce chemin vers
  /// son interface web (HTML) au lieu de repondre en JSON, ce qui ressemble
  /// a un identifiant/mot de passe invalide alors que ce n'en est pas un.
  String _sanitizeUrl(String url) {
    var sanitized = url.trim();
    while (sanitized.endsWith('/')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }
    return sanitized;
  }

  /// Charge les identifiants stockes localement (ou le repli
  /// credentials.dart) en memoire, sans authentifier aupres du NAS -- pur
  /// I/O local (secure storage), donc rapide et sans dependance reseau.
  /// Permet a AppState.initialize() de peupler hasCredentials (et donc
  /// isLoggedIn) avant le premier rendu, pour eviter le flash de l'ecran de
  /// connexion pendant que l'authentification live (potentiellement lente,
  /// voir authenticate()) se termine en tache de fond.
  Future<void> loadStoredCredentials() async {
    final creds = await SecureStorage.getCredentials();
    final storedUrl = creds['url'];
    _baseUrl = storedUrl != null ? _sanitizeUrl(storedUrl) : null;
    _username = creds['username'];
    _password = creds['password'];

    if (_baseUrl == null || _username == null || _password == null) {
      _baseUrl = _sanitizeUrl(kNavidromeUrl);
      _username = kNavidromeUser;
      _password = kNavidromePass;
      await SecureStorage.saveCredentials(_baseUrl!, _username!, _password!);
    } else if (_baseUrl != storedUrl) {
      // Corrige une URL deja sauvegardee avec un slash final.
      await SecureStorage.saveCredentials(_baseUrl!, _username!, _password!);
    }
    _apiKey = await SecureStorage.getApiKey();
    _newSession();
    // Ancien sel fixe (<= 1.2.x) : plus utilise, on ne le laisse pas trainer.
    await SecureStorage.deleteSalt();
  }

  /// Nouveau sel aleatoire et jeton md5(mdp + sel) correspondant. Avant, le
  /// sel etait fixe a vie pour que les URL ecrites dans le cache restent
  /// valides et que le cache d'images serve d'un lancement a l'autre ; les
  /// caches ne contiennent plus que des ids (SubsonicRefs) et le cache
  /// d'images utilise l'id de pochette comme cle (coverImageProvider), donc
  /// un jeton intercepte ne vaut plus que pour la session en cours.
  void _newSession() {
    if (_password == null) {
      _salt = null;
      _sessionToken = null;
      _syncClient();
      return;
    }
    _salt = _generateSalt();
    _sessionToken = md5.convert(utf8.encode(_password! + _salt!)).toString();
    _syncClient();
  }

  /// Recopie URL et authentification courantes dans le client.
  void _syncClient() {
    _client.baseUrl = _baseUrl;
    _client.authParams = _canBuildUrls ? _authParams : const {};
  }

  /// Authentifie aupres du NAS avec les identifiants deja charges en
  /// memoire (voir loadStoredCredentials()). Appel reseau, peut prendre
  /// jusqu'a 10s (timeout) si le NAS est lent/injoignable.
  Future<bool> authenticate() async {
    if (_baseUrl != null && _username != null && _password != null) {
      return await _authenticate();
    }
    return false;
  }

  Future<bool> loadCredentials() async {
    await loadStoredCredentials();
    return await authenticate();
  }

  Future<bool> saveCredentials(
      String url, String username, String password) async {
    final cleanUrl = _sanitizeUrl(url);
    // Un nouveau serveur en http:// doit etre sur Tailscale ou le reseau
    // local : sinon le jeton (et la musique) circuleraient en clair sur
    // Internet. Les identifiants deja enregistres ne sont pas re-verifies,
    // pour ne bloquer personne a la mise a jour.
    if (!isCleartextAllowed(cleanUrl)) return false;
    await SecureStorage.saveCredentials(cleanUrl, username, password);
    _baseUrl = cleanUrl;
    _username = username;
    _password = password;
    _newSession();
    return await _authenticate();
  }

  Future<void> clearCredentials() async {
    await SecureStorage.clear();
    _baseUrl = null;
    _username = null;
    _password = null;
    _token = null;
    _salt = null;
    _sessionToken = null;
    _apiKey = null;
    _syncClient();
  }

  /// Cle d'API OpenSubsonic (Navidrome recent : Parametres > Cles d'API).
  /// Optionnelle : sans cle, l'app continue d'utiliser le jeton md5. Avec,
  /// les URL ne contiennent plus rien de derive du mot de passe et la cle
  /// peut etre revoquee cote serveur sans changer le mot de passe. null ou
  /// vide = revenir au jeton.
  Future<bool> setApiKey(String? apiKey) async {
    final clean = apiKey?.trim();
    _apiKey = (clean == null || clean.isEmpty) ? null : clean;
    await SecureStorage.saveApiKey(_apiKey);
    _syncClient();
    return await _authenticate();
  }

  bool get usesApiKey => _apiKey != null;

  /// Pose des identifiants sans passer par le stockage securise (absent des
  /// tests unitaires).
  @visibleForTesting
  void debugSetCredentials(String url, String username, String password,
      {String? apiKey}) {
    _baseUrl = _sanitizeUrl(url);
    _username = username;
    _password = password;
    _apiKey = apiKey;
    _newSession();
  }

  /// Vrai si le serveur annonce l'extension OpenSubsonic
  /// "apiKeyAuthentication" (getOpenSubsonicExtensions, sans
  /// authentification). Permet de ne proposer la cle d'API que quand la
  /// version de Navidrome la gere.
  Future<bool> supportsApiKeyAuth() async {
    if (_baseUrl == null) return false;
    _syncClient();
    try {
      final extensions = await _client.openSubsonicExtensions();
      return extensions.any((e) => e['name'] == 'apiKeyAuthentication');
    } on SubsonicException catch (e) {
      debugPrint('supportsApiKeyAuth error: $e');
      return false;
    }
  }

  /// Parametres d'authentification de la session en cours, a transmettre
  /// au relais pour lancer une soiree (il les verifie par un ping puis les
  /// oublie). Jamais le mot de passe : seulement le jeton md5 + sel, ou la
  /// cle d'API. Null tant que rien n'est charge.
  Map<String, String>? get authParams => _canBuildUrls ? _authParams : null;

  /// Parametres d'authentification Subsonic de la session en cours.
  Map<String, String> get _authParams => _apiKey != null
      ? {'apiKey': _apiKey!}
      : {'u': _username!, 't': _sessionToken!, 's': _salt!};

  bool get _canBuildUrls =>
      _baseUrl != null &&
      (_apiKey != null ||
          (_username != null && _sessionToken != null && _salt != null));

  Future<bool> _authenticate() async {
    if (_baseUrl == null || _username == null || _password == null) {
      return false;
    }
    if (_sessionToken == null) _newSession();

    // _token ne doit etre pose qu'apres confirmation du serveur, sinon
    // isConnected (qui se base sur _token != null) reste vrai meme apres un
    // refus explicite (identifiants invalides = reponse HTTP 200 avec status
    // "failed", pas une exception).
    final candidateToken = _sessionToken!;
    _syncClient();

    try {
      await _client.ping();
      _token = candidateToken;
      return true;
    } on SubsonicException catch (e) {
      debugPrint('Navidrome auth error: $e');
    }
    _token = null;
    return false;
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List.generate(6, (_) => random.nextInt(256));
    return base64Url.encode(bytes).substring(0, 8);
  }

  /// Toute la bibliotheque de titres. [onBatch] recoit chaque page de
  /// titres des qu'elle arrive (avant la fin de la synchro complete) : permet
  /// a l'appelant d'afficher la bibliotheque progressivement.
  ///
  /// Les titres sont pagines via search3 (requete vide, 500 par page) au
  /// lieu d'un getAlbum par album : quelques dizaines de requetes au lieu de
  /// 1500+ sur la bibliotheque du NAS, et plus de rafales de handshakes TLS
  /// concurrents sur le tunnel Tailscale. La liste des albums (une requete
  /// par 500 albums) sert seulement a retrouver l'artiste de chaque album.
  ///
  /// Leve une [SubsonicException] si une page echoue : l'appelant garde sa
  /// bibliotheque precedente au lieu d'en enregistrer une tronquee.
  Future<List<Track>> fetchAllTracks(
      {void Function(List<Track> batch)? onBatch}) async {
    if (!isConnected) {
      throw const SubsonicException('pas connecte au serveur');
    }
    _syncClient();
    final requestsBefore = _client.requestCount;
    final albums = await _client.allAlbums();
    final albumArtists = <String, String?>{
      for (final album in albums)
        album['id'].toString(): album['artist']?.toString(),
    };

    final allTracks = <Track>[];
    await _client.allSongs(onPage: (page) {
      final batch = page.map((song) {
        final albumId = song['albumId']?.toString();
        return trackFromSubsonic(song,
            albumArtist: albumId == null ? null : albumArtists[albumId]);
      }).toList();
      allTracks.addAll(batch);
      onBatch?.call(batch);
    });

    // Filet de securite : un serveur qui ne renverrait rien pour une
    // recherche vide (vieux Navidrome, autre serveur Subsonic) repasse par
    // l'ancienne methode, un getAlbum par album.
    if (allTracks.isEmpty && albums.isNotEmpty) {
      debugPrint('search3 vide : synchro album par album');
      await _fetchTracksAlbumByAlbum(albums, allTracks, onBatch);
    }

    debugPrint('TOTAL TRACKS: ${allTracks.length} '
        '(${albums.length} albums, '
        '${_client.requestCount - requestsBefore} requetes)');
    return allTracks;
  }

  /// Ancienne synchro : un getAlbum par album, 16 en parallele (au-dela,
  /// des handshakes TLS concurrents sur le tunnel Tailscale echouaient).
  Future<void> _fetchTracksAlbumByAlbum(
    List<Map<String, dynamic>> albums,
    List<Track> allTracks,
    void Function(List<Track> batch)? onBatch,
  ) async {
    const batchSize = 16;
    for (var i = 0; i < albums.length; i += batchSize) {
      final batch = albums.skip(i).take(batchSize);
      final results = await Future.wait(batch.map((album) async {
        final albumId = album['id'].toString();
        final full = await _client.album(albumId);
        return SubsonicClient.listOf(full['song'])
            .map((song) => trackFromSubsonic(song,
                albumArtist: album['artist']?.toString(), albumId: albumId))
            .toList();
      }));
      final batchTracks = [for (final tracks in results) ...tracks];
      allTracks.addAll(batchTracks);
      onBatch?.call(batchTracks);
    }
  }

  /// Les [count] albums les plus recemment ajoutes (getAlbumList2?type=newest),
  /// un seul aller-retour HTTP -- utilise pour rafraichir juste ce qu'un
  /// telechargement vient d'ajouter sans refaire une synchro complete de
  /// toute la bibliotheque (voir MusicService.syncRecentlyAdded).
  Future<List<Map<String, dynamic>>> fetchRecentAlbums({int count = 5}) async {
    if (!isConnected) return [];
    try {
      final albums = await _client.albumList2(type: 'newest', size: count);
      return albums.map(albumSummaryFromSubsonic).toList();
    } on SubsonicException catch (e) {
      debugPrint('fetchRecentAlbums error: $e');
      return [];
    }
  }

  /// Cherche un titre precis via search3.view (recherche plein texte
  /// Subsonic), pour le retrouver juste apres un telechargement automatique
  /// sans attendre qu'il apparaisse dans fetchRecentAlbums -- un titre
  /// telecharge sans album connu (voir DownloadWorkerService) atterrit dans
  /// un dossier partage par artiste (album = artiste), dont la date de
  /// creation Navidrome ne bouge plus une fois ce "faux album" deja cree :
  /// un 2e titre du meme artiste sans album ne remonte alors plus jamais
  /// dans les "derniers ajouts" (retour utilisateur : titre bien telecharge
  /// cote NAS mais l'app le montre indefiniment comme indisponible).
  Future<Track?> findTrack(String artist, String title) async {
    if (!isConnected) return null;
    try {
      final songs = await _client.searchSongs(title, count: 20);
      // Matching flou (MatchingService, meme algo que partout ailleurs dans
      // l'app) plutot qu'une egalite stricte : un titre telecharge via
      // YouTube porte souvent des tags legerement differents de la requete
      // Deezer d'origine (accents, ponctuation, "(Official Audio)", version
      // remasterisee...) -- l'egalite stricte precedente ratait alors le
      // titre pourtant bien present sur le NAS juste apres son telechargement
      // (retour utilisateur : le bouton "telecharger" reapparaissait au lieu
      // de refleter le titre comme disponible).
      for (final json in songs) {
        final songTitle = json['title']?.toString() ?? '';
        if (!MatchingService.titlesMatch(songTitle, title)) continue;
        final songArtist = json['artist']?.toString() ?? '';
        if (artist.trim().isEmpty ||
            MatchingService.artistsMatch(songArtist, artist)) {
          return trackFromSubsonic(json);
        }
      }
    } on SubsonicException catch (e) {
      debugPrint('findTrack error: $e');
    }
    return null;
  }

  /// Titres d'un album, [] en cas d'echec. Les erreurs reseau transitoires
  /// (ex: "Connection terminated during handshake" sur le tunnel Tailscale)
  /// sont deja reessayees par SubsonicClient.
  Future<List<Track>> fetchAlbumTracks(String albumId,
      {String? albumArtist}) async {
    if (!isConnected) return [];
    try {
      final album = await _client.album(albumId);
      return SubsonicClient.listOf(album['song'])
          .map((json) => trackFromSubsonic(json,
              albumArtist: albumArtist, albumId: albumId))
          .toList();
    } on SubsonicException catch (e) {
      debugPrint('fetchAlbumTracks error (album $albumId): $e');
      return [];
    }
  }

  /// Bitrate cible pour la lecture en direct (streaming) : sans ca, Navidrome
  /// renvoie le fichier source tel quel (souvent du FLAC/lossless) au lieu de
  /// le transcoder, ce que le tunnel Tailscale en 4G/5G ne peut pas toujours
  /// suivre en continu. Resultat observe : micro-coupures de plus en plus
  /// frequentes apres quelques titres, jusqu'au crash du player. Les
  /// telechargements hors-ligne (MusicService.downloadTrack) appliquaient
  /// deja ce meme transcodage 192kbps mp3 ; on aligne la lecture en direct
  /// dessus.
  static const int streamMaxBitRateKbps = 192;

  /// URL de lecture construite a la demande (jamais stockee : voir
  /// SubsonicRefs). Disponible des que les identifiants sont charges, meme
  /// avant la reponse du ping, pour que la bibliotheque en cache soit
  /// jouable/affichable tout de suite au demarrage.
  String getStreamUrl(String id, {int? maxBitRateKbps, String? format}) {
    if (!_canBuildUrls) return '';
    final effectiveBitRate = maxBitRateKbps ?? streamMaxBitRateKbps;
    final effectiveFormat = format ?? 'mp3';
    return Uri.parse('$_baseUrl/rest/stream.view').replace(queryParameters: {
      'id': id,
      ..._authParams,
      'v': '1.16.1',
      'c': 'vinland',
      if (effectiveFormat != 'raw') 'maxBitRate': '$effectiveBitRate',
      'format': effectiveFormat,
    }).toString();
  }

  String getCoverUrl(String id) {
    if (!_canBuildUrls) return '';
    return Uri.parse('$_baseUrl/rest/getCoverArt.view')
        .replace(queryParameters: {
      'id': id,
      ..._authParams,
      'v': '1.16.1',
      'c': 'vinland',
    }).toString();
  }

  /// Signale une lecture a Navidrome (scrobble.view, submission=true) : sans
  /// ca, playCount/date de derniere ecoute ne sont connus que localement par
  /// utilisateur (MusicService.recordPlay), jamais remontes au NAS. La regle
  /// de suppression automatique des morceaux peu ecoutes (voir download-worker)
  /// en a besoin pour savoir ce qui a reellement ete joue, tous appareils
  /// confondus.
  /// Signale une lecture a Navidrome (scrobble.view, submission=true) : sans
  /// ca, playCount/date de derniere ecoute ne sont connus que localement par
  /// utilisateur (MusicService.recordPlay), jamais remontes au NAS. La regle
  /// de suppression automatique des morceaux peu ecoutes (voir download-worker)
  /// en a besoin pour savoir ce qui a reellement ete joue, tous appareils
  /// confondus.
  Future<void> scrobble(String trackId) async {
    if (!isConnected) return;
    try {
      await _client.scrobble(_cleanId(trackId));
    } on SubsonicException catch (e) {
      debugPrint('scrobble error: $e');
    }
  }

  /// Paroles brutes du titre (voir SubsonicClient.lyricsBySongId). Liste
  /// vide si pas de connexion, pas de paroles, ou serveur trop ancien pour
  /// l'extension (il repond alors par une erreur).
  Future<List<Map<String, dynamic>>> lyrics(String trackId) async {
    if (!isConnected) return const [];
    try {
      return await _client.lyricsBySongId(_cleanId(trackId));
    } on SubsonicException catch (e) {
      debugPrint('lyrics error: $e');
      return const [];
    }
  }

  static String _cleanId(String trackId) =>
      trackId.replaceFirst('navidrome_', '');

  /// Execute un appel d'ecriture et renvoie false (au lieu de croire a un
  /// succes) si le serveur l'a refuse ou n'a pas repondu.
  Future<bool> _write(String label, Future<void> Function() call) async {
    if (!isConnected) return false;
    try {
      await call();
      return true;
    } on SubsonicException catch (e) {
      debugPrint('$label error: $e');
      return false;
    }
  }

  Future<bool> starTrack(String trackId) =>
      _write('starTrack', () => _client.star(id: _cleanId(trackId)));

  Future<bool> unstarTrack(String trackId) =>
      _write('unstarTrack', () => _client.unstar(id: _cleanId(trackId)));

  Future<Map<String, DateTime?>> fetchStarredTrackIds() async {
    if (!isConnected) return {};
    try {
      final starred = await _client.starred2();
      return {
        for (final s in starred['song']!)
          'navidrome_${s['id']}': s['starred'] != null
              ? DateTime.tryParse(s['starred'].toString())
              : null
      };
    } on SubsonicException catch (e) {
      debugPrint('fetchStarred error: $e');
      return {};
    }
  }

  /// Titres likes du serveur avec leurs infos completes (getStarred2 les
  /// renvoie deja) : permet d'adopter un like fait sur un autre appareil
  /// pour un titre que cet appareil ne connait pas encore (voir
  /// MusicService.lightSync).
  Future<List<Track>> fetchStarredTracks() async {
    if (!isConnected) return [];
    try {
      final starred = await _client.starred2();
      return [
        for (final s in starred['song']!)
          trackFromSubsonic(s)
            ..dateAdded = s['starred'] != null
                ? DateTime.tryParse(s['starred'].toString())
                : null
      ];
    } on SubsonicException catch (e) {
      debugPrint('fetchStarredTracks error: $e');
      return [];
    }
  }

  Future<bool> starAlbum(String albumId) =>
      _write('starAlbum', () => _client.star(albumId: albumId));

  Future<bool> unstarAlbum(String albumId) =>
      _write('unstarAlbum', () => _client.unstar(albumId: albumId));

  Future<Set<String>> fetchStarredAlbumIds() async {
    if (!isConnected) return {};
    try {
      final starred = await _client.starred2();
      return starred['album']!.map((a) => 'navidrome_${a['id']}').toSet();
    } on SubsonicException catch (e) {
      debugPrint('fetchStarredAlbumIds error: $e');
      return {};
    }
  }

  /// Playlists visibles pour l'utilisateur connecte : les siennes + celles
  /// que d'autres utilisateurs ont marquees publiques (comportement standard
  /// getPlaylists.view sans parametre "username"). C'est cette liste qui
  /// permet de decouvrir les "amis" (= tout autre "owner" present ici) sans
  /// avoir besoin d'un compte admin. [] en cas d'echec : pour decider de
  /// creer une playlist, utiliser [fetchPlaylistsOrNull].
  Future<List<Map<String, dynamic>>> fetchPlaylists() async =>
      await fetchPlaylistsOrNull() ?? [];

  /// Comme [fetchPlaylists], mais null si le serveur n'a pas repondu. Une
  /// liste vide due a une coupure faisait croire qu'une playlist miroir
  /// (likes, ecoutes recentes, epingles...) n'existait pas encore, et l'app
  /// en creait un doublon a chaque coupure.
  Future<List<Map<String, dynamic>>?> fetchPlaylistsOrNull() async {
    if (!isConnected) return null;
    try {
      final playlists = await _client.playlists();
      return playlists.map(playlistSummaryFromSubsonic).toList();
    } on SubsonicException catch (e) {
      debugPrint('fetchPlaylists error: $e');
      return null;
    }
  }

  /// Ids (prefixes 'navidrome_', dans l'ordre du serveur) des titres d'une
  /// playlist, qu'elle appartienne a l'utilisateur courant ou (si publique)
  /// a un autre utilisateur.
  Future<List<String>> fetchPlaylistSongIds(String playlistId) async {
    if (!isConnected) return [];
    try {
      final entries = await _client.playlistEntries(playlistId);
      return entries.map((s) => 'navidrome_${s['id']}').toList();
    } on SubsonicException catch (e) {
      debugPrint('fetchPlaylistSongIds error: $e');
      return [];
    }
  }

  /// Cree une playlist sur le serveur et retourne son id, ou null en cas
  /// d'echec. `comment` sert de marqueur interne stable (ex: identifier la
  /// playlist miroir des likes) puisque le nom, lui, est modifiable par
  /// l'utilisateur.
  Future<String?> createServerPlaylist(String name,
      {String? comment, bool public = false}) async {
    if (!isConnected) return null;
    try {
      final id = await _client.createPlaylist(name);
      if (comment != null || public) {
        await setPlaylistMeta(id, comment: comment, public: public);
      }
      return id;
    } on SubsonicException catch (e) {
      debugPrint('createServerPlaylist error: $e');
      return null;
    }
  }

  Future<bool> setPlaylistMeta(String playlistId,
          {String? name, String? comment, bool? public}) =>
      _write(
          'setPlaylistMeta',
          () => _client.updatePlaylist(playlistId,
              name: name, comment: comment, public: public));

  /// Remplace entierement le contenu d'une playlist par `cleanTrackIds`
  /// (sans le prefixe 'navidrome_', dans l'ordre voulu). Utilise
  /// songIndexToRemove + songIdToAdd en un seul appel plutot que de
  /// supprimer/recreer la playlist, pour ne pas perdre son id/son statut
  /// public en cours de route. En POST : en GET, l'URL depassait la limite
  /// du serveur au-dela de quelques centaines de titres.
  Future<bool> replacePlaylistSongs(
      String playlistId, List<String> cleanTrackIds) async {
    if (!isConnected) return false;
    try {
      // Contenu actuel lu sans repli sur [] : si la lecture echoue, on ne
      // doit pas ajouter les titres par-dessus ceux deja presents.
      final current = (await _client.playlistEntries(playlistId))
          .map((s) => s['id'].toString())
          .toList();
      if (current.join(',') == cleanTrackIds.join(',')) return true;

      await _client.updatePlaylist(
        playlistId,
        songIndexToRemove: [for (var i = current.length - 1; i >= 0; i--) i],
        songIdToAdd: cleanTrackIds,
      );
      return true;
    } on SubsonicException catch (e) {
      debugPrint('replacePlaylistSongs error: $e');
      return false;
    }
  }

  Future<bool> deleteServerPlaylist(String playlistId) =>
      _write('deleteServerPlaylist', () => _client.deletePlaylist(playlistId));

  /// Titres proches de [songId] presents sur le serveur, pour la radio du
  /// mode Soiree. getSimilarSongs d'abord (a partir du titre), puis
  /// getSimilarSongs2 a partir de son artiste : selon la version de
  /// Navidrome et ses agents, l'un peut repondre vide et pas l'autre.
  /// [] si rien ou en cas d'erreur (la radio essaie alors autre chose).
  Future<List<Track>> similarSongs(String songId, {int count = 30}) async {
    if (!isConnected) return const [];
    try {
      var songs = await _client.similarSongs(songId, count: count);
      if (songs.isEmpty) {
        final artistId = (await _client.song(songId))['artistId']?.toString();
        if (artistId != null && artistId.isNotEmpty) {
          songs = await _client.similarSongs2(artistId, count: count);
        }
      }
      return songs.map(trackFromSubsonic).toList();
    } on SubsonicException catch (e) {
      debugPrint('similarSongs error: $e');
      return const [];
    }
  }
}
