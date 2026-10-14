import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'subsonic_exception.dart';

/// Client bas niveau de l'API Subsonic (Navidrome).
///
/// Tout appel passe par [parseResponse] : une reponse `status: failed`
/// devient une [SubsonicException] au lieu d'etre prise pour un succes, et
/// une erreur reseau devient une [SubsonicNetworkException], seule erreur
/// reessayee. Le [http.Client] est injecte pour que les tests puissent
/// rejouer des reponses du serveur (MockClient) sans NAS.
///
/// L'authentification (jeton md5 ou cle d'API) reste geree par
/// NavidromeService, qui renseigne [baseUrl] et [authParams].
class SubsonicClient {
  static const String apiVersion = '1.16.1';
  static const String clientName = 'vinland';

  /// Taille des pages de la synchro de bibliotheque : maximum accepte par
  /// Navidrome pour search3 et getAlbumList2.
  static const int pageSize = 500;

  final http.Client _http;
  final int maxRetries;
  final Duration retryDelay;
  final Future<void> Function(Duration) _sleep;

  /// URL du serveur, sans slash final.
  String? baseUrl;

  /// u/t/s (jeton) ou apiKey (cle OpenSubsonic).
  Map<String, String> authParams = const {};

  /// Nombre de requetes HTTP envoyees (essais compris) : sert a mesurer ce
  /// que coute une synchro de bibliotheque.
  int requestCount = 0;

  SubsonicClient({
    http.Client? httpClient,
    this.maxRetries = 2,
    this.retryDelay = const Duration(milliseconds: 400),
    Future<void> Function(Duration)? sleep,
  })  : _http = httpClient ?? http.Client(),
        _sleep = sleep ?? Future<void>.delayed;

  Map<String, String> _commonParams({bool authenticated = true}) => {
        if (authenticated) ...authParams,
        'v': apiVersion,
        'c': clientName,
        'f': 'json',
      };

  /// URL d'un appel REST. Les valeurs sont encodees par [Uri] (un pseudo ou
  /// une recherche contenant `&`, `=` ou un espace ne casse pas la requete).
  /// Une valeur [Iterable] repete le parametre (songIdToAdd=1&songIdToAdd=2).
  Uri uri(String endpoint,
      {Map<String, Object> params = const {}, bool authenticated = true}) {
    return _endpoint(endpoint).replace(queryParameters: {
      ..._commonParams(authenticated: authenticated),
      ...params,
    });
  }

  Uri _endpoint(String endpoint) {
    final base = baseUrl;
    if (base == null) {
      throw const SubsonicException('aucun serveur configure');
    }
    return Uri.parse('$base/rest/$endpoint');
  }

  /// Appel GET, reessaye sur erreur reseau si [retry].
  Future<Map<String, dynamic>> get(
    String endpoint, {
    Map<String, Object> params = const {},
    Duration timeout = const Duration(seconds: 15),
    bool retry = true,
    bool authenticated = true,
  }) {
    final url = uri(endpoint, params: params, authenticated: authenticated);
    return _send(() => _http.get(url).timeout(timeout), retry: retry);
  }

  /// Appel POST `application/x-www-form-urlencoded` : les parametres (et
  /// l'authentification) passent dans le corps, sans limite de longueur
  /// d'URL. Necessaire pour remplacer le contenu d'une grosse playlist, que
  /// le GET faisait echouer au-dela de quelques centaines de titres.
  Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, Object> params = const {},
    Duration timeout = const Duration(seconds: 20),
    bool retry = false,
  }) {
    final url = _endpoint(endpoint);
    final all = <String, Object>{..._commonParams(), ...params};
    final body = Uri(queryParameters: all).query;
    return _send(
      () => _http
          .post(url,
              headers: const {
                'Content-Type': 'application/x-www-form-urlencoded',
              },
              body: body)
          .timeout(timeout),
      retry: retry,
    );
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request, {
    required bool retry,
  }) async {
    var attempt = 0;
    while (true) {
      http.Response response;
      try {
        requestCount++;
        response = await request();
      } catch (e) {
        // Tout ce qui echoue avant d'avoir une reponse est reseau (coupure,
        // timeout, handshake TLS...) : on reessaie avec un delai croissant.
        if (!retry || attempt >= maxRetries) {
          throw SubsonicNetworkException(e);
        }
        await _sleep(retryDelay * (1 << attempt));
        attempt++;
        continue;
      }
      return parseResponse(response);
    }
  }

  /// Extrait `subsonic-response` d'une reponse, ou leve une
  /// [SubsonicException] si le serveur a refuse l'appel.
  static Map<String, dynamic> parseResponse(http.Response response) {
    if (response.statusCode != 200) {
      throw SubsonicException('reponse HTTP inattendue',
          httpStatus: response.statusCode);
    }
    Object? data;
    try {
      data = jsonDecode(response.body);
    } on FormatException {
      // Typiquement la page HTML de Navidrome (URL mal formee, proxy...).
      throw const SubsonicException('reponse non JSON');
    }
    final body = data is Map ? data['subsonic-response'] : null;
    if (body is! Map) {
      throw const SubsonicException('reponse sans subsonic-response');
    }
    final result = Map<String, dynamic>.from(body);
    if (result['status'] != 'ok') {
      final error = result['error'];
      final code = error is Map ? error['code'] : null;
      throw SubsonicException(
        (error is Map ? error['message']?.toString() : null) ??
            'appel refuse par le serveur',
        code: code is int ? code : int.tryParse('$code'),
      );
    }
    return result;
  }

  /// Liste JSON d'objets, meme si le serveur renvoie un objet seul ou rien.
  static List<Map<String, dynamic>> listOf(Object? value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (value is Map) return [Map<String, dynamic>.from(value)];
    return const [];
  }

  // ---------------------------------------------------------------------
  // Appels types
  // ---------------------------------------------------------------------

  /// Verifie les identifiants. Pas de retry : l'ecran de connexion doit
  /// repondre vite, et AppState relance de lui-meme au retour du reseau.
  Future<void> ping() async {
    await get('ping.view', timeout: const Duration(seconds: 10), retry: false);
  }

  /// Extensions OpenSubsonic annoncees par le serveur. Appel public (sans
  /// authentification) : il doit repondre meme avec une cle d'API refusee.
  Future<List<Map<String, dynamic>>> openSubsonicExtensions() async {
    final data = await get('getOpenSubsonicExtensions.view',
        timeout: const Duration(seconds: 10),
        retry: false,
        authenticated: false);
    return listOf(data['openSubsonicExtensions']);
  }

  Future<List<Map<String, dynamic>>> albumList2({
    required String type,
    int size = pageSize,
    int offset = 0,
  }) async {
    final data = await get('getAlbumList2.view', params: {
      'type': type,
      'size': '$size',
      'offset': '$offset',
    });
    return listOf((data['albumList2'] as Map?)?['album']);
  }

  /// Tous les albums, page par page. Une page en erreur fait echouer
  /// l'ensemble au lieu de renvoyer une liste tronquee.
  Future<List<Map<String, dynamic>>> allAlbums() async {
    final albums = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await albumList2(
          type: 'alphabeticalByName', size: pageSize, offset: offset);
      albums.addAll(page);
      if (page.length < pageSize) return albums;
      offset += pageSize;
    }
  }

  /// Album avec ses titres (cle `song`).
  Future<Map<String, dynamic>> album(String id) async {
    final data = await get('getAlbum.view', params: {'id': id});
    final album = data['album'];
    if (album is! Map) throw const SubsonicException('album absent');
    return Map<String, dynamic>.from(album);
  }

  /// Titres trouves par search3 (ni artistes ni albums).
  Future<List<Map<String, dynamic>>> searchSongs(
    String query, {
    int count = 20,
    int offset = 0,
  }) async {
    final data = await get('search3.view', params: {
      'query': query,
      'songCount': '$count',
      'songOffset': '$offset',
      'artistCount': '0',
      'albumCount': '0',
    });
    return listOf((data['searchResult3'] as Map?)?['song']);
  }

  /// Toute la bibliotheque de titres via search3 avec une requete vide
  /// (Navidrome renvoie alors tout, page par page) : une requete par 500
  /// titres au lieu d'un getAlbum par album. [onPage] recoit chaque page des
  /// son arrivee. Une page en erreur fait echouer toute la synchro.
  Future<List<Map<String, dynamic>>> allSongs({
    void Function(List<Map<String, dynamic>> page)? onPage,
  }) async {
    final songs = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await searchSongs('', count: pageSize, offset: offset);
      songs.addAll(page);
      if (page.isNotEmpty) onPage?.call(page);
      if (page.length < pageSize) return songs;
      offset += pageSize;
    }
  }

  /// Fiche d'un titre (cle `artistId` utile a [similarSongs2]).
  Future<Map<String, dynamic>> song(String id) async {
    final data = await get('getSong.view', params: {'id': id});
    final song = data['song'];
    if (song is! Map) throw const SubsonicException('titre absent');
    return Map<String, dynamic>.from(song);
  }

  /// Titres proches d'un titre, d'un album ou d'un artiste. Navidrome les
  /// tire de ses agents (Last.fm...) : liste vide si aucun n'est configure.
  Future<List<Map<String, dynamic>>> similarSongs(String id,
      {int count = 30}) async {
    final data = await get('getSimilarSongs.view',
        params: {'id': id, 'count': '$count'});
    return listOf((data['similarSongs'] as Map?)?['song']);
  }

  /// Comme [similarSongs], a partir d'un artiste (version ID3).
  Future<List<Map<String, dynamic>>> similarSongs2(String artistId,
      {int count = 30}) async {
    final data = await get('getSimilarSongs2.view',
        params: {'id': artistId, 'count': '$count'});
    return listOf((data['similarSongs2'] as Map?)?['song']);
  }

  /// Titres et albums likes (cles `song` et `album`).
  Future<Map<String, List<Map<String, dynamic>>>> starred2() async {
    final data = await get('getStarred2.view');
    final starred = data['starred2'] as Map?;
    return {
      'song': listOf(starred?['song']),
      'album': listOf(starred?['album']),
    };
  }

  Future<void> star({String? id, String? albumId}) async {
    await get('star.view', params: {
      if (id != null) 'id': id,
      if (albumId != null) 'albumId': albumId,
    });
  }

  Future<void> unstar({String? id, String? albumId}) async {
    await get('unstar.view', params: {
      if (id != null) 'id': id,
      if (albumId != null) 'albumId': albumId,
    });
  }

  /// Pas de retry : une lecture comptee deux fois fausserait les compteurs
  /// d'ecoute dont depend la suppression automatique cote NAS.
  Future<void> scrobble(String id) async {
    await get('scrobble.view',
        params: {'id': id, 'submission': 'true'},
        timeout: const Duration(seconds: 10),
        retry: false);
  }

  /// Paroles d'un titre (extension OpenSubsonic `songLyrics`) : une entree
  /// par langue, cle `synced`, `offset` (ms) et `line` (`start` en ms,
  /// `value`). Navidrome les lit dans les tags du fichier ou un `.lrc` a
  /// cote. Liste vide si le titre n'en a pas.
  Future<List<Map<String, dynamic>>> lyricsBySongId(String id) async {
    final data = await get('getLyricsBySongId.view',
        params: {'id': id}, timeout: const Duration(seconds: 10));
    return listOf((data['lyricsList'] as Map?)?['structuredLyrics']);
  }

  Future<List<Map<String, dynamic>>> playlists() async {
    final data = await get('getPlaylists.view');
    return listOf((data['playlists'] as Map?)?['playlist']);
  }

  /// Titres d'une playlist, dans l'ordre du serveur.
  Future<List<Map<String, dynamic>>> playlistEntries(String id) async {
    final data = await get('getPlaylist.view', params: {'id': id});
    return listOf((data['playlist'] as Map?)?['entry']);
  }

  /// Cree une playlist vide et renvoie son id. Pas de retry : un essai dont
  /// seule la reponse s'est perdue creerait un doublon.
  Future<String> createPlaylist(String name) async {
    final data =
        await get('createPlaylist.view', params: {'name': name}, retry: false);
    final id = (data['playlist'] as Map?)?['id']?.toString();
    if (id == null) throw const SubsonicException('playlist creee sans id');
    return id;
  }

  /// Modifie une playlist en POST. Les retraits d'index ne sont pas
  /// idempotents (rejouer la requete retirerait d'autres titres) : pas de
  /// retry des qu'on touche au contenu.
  Future<void> updatePlaylist(
    String playlistId, {
    String? name,
    String? comment,
    bool? public,
    List<int> songIndexToRemove = const [],
    List<String> songIdToAdd = const [],
  }) async {
    final editsSongs = songIndexToRemove.isNotEmpty || songIdToAdd.isNotEmpty;
    await post('updatePlaylist.view',
        params: {
          'playlistId': playlistId,
          if (name != null) 'name': name,
          if (comment != null) 'comment': comment,
          if (public != null) 'public': '$public',
          if (songIndexToRemove.isNotEmpty)
            'songIndexToRemove': songIndexToRemove.map((i) => '$i').toList(),
          if (songIdToAdd.isNotEmpty) 'songIdToAdd': songIdToAdd,
        },
        retry: !editsSongs);
  }

  /// Pas de retry : si seule la reponse s'est perdue, le second essai
  /// echouerait (playlist introuvable) alors que la suppression a eu lieu.
  Future<void> deletePlaylist(String id) async {
    await get('deletePlaylist.view', params: {'id': id}, retry: false);
  }

  void close() => _http.close();
}
