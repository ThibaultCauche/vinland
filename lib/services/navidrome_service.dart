import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../models/track.dart';
import 'secure_storage.dart';
import '../config/credentials.dart';

class NavidromeService {
  static final NavidromeService _instance = NavidromeService._internal();
  factory NavidromeService() => _instance;
  NavidromeService._internal();

  String? _baseUrl;
  String? _username;
  String? _password;
  String? _token;
  String? _salt;

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

  Future<bool> loadCredentials() async {
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

    if (_baseUrl != null && _username != null && _password != null) {
      return await _authenticate();
    }
    return false;
  }

  Future<bool> saveCredentials(
      String url, String username, String password) async {
    final cleanUrl = _sanitizeUrl(url);
    await SecureStorage.saveCredentials(cleanUrl, username, password);
    _baseUrl = cleanUrl;
    _username = username;
    _password = password;
    return await _authenticate();
  }

  Future<void> clearCredentials() async {
    await SecureStorage.clear();
    _baseUrl = null;
    _username = null;
    _password = null;
    _token = null;
    _salt = null;
  }

  Future<bool> _authenticate() async {
    if (_baseUrl == null || _username == null || _password == null)
      return false;

    // Reutilise le meme salt entre les sessions : sinon les URLs de
    // stream/cover changent a chaque demarrage et le cache image de Flutter
    // ne peut jamais servir (flash de toutes les pochettes a chaque sync).
    _salt = await SecureStorage.getSalt();
    if (_salt == null) {
      _salt = _generateSalt();
      await SecureStorage.saveSalt(_salt!);
    }
    // Calcule dans une variable locale d'abord : _token ne doit etre pose
    // qu'apres confirmation du serveur, sinon isConnected (qui se base sur
    // _token != null) reste vrai meme apres un refus explicite (identifiants
    // invalides = reponse HTTP 200 avec status "failed", pas une exception).
    final candidateToken = md5.convert(utf8.encode(_password! + _salt!)).toString();

    final url = Uri.parse(
      '$_baseUrl/rest/ping.view?u=$_username&t=$candidateToken&s=$_salt&v=1.16.1&c=vinland&f=json',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['subsonic-response']?['status'] == 'ok') {
          _token = candidateToken;
          return true;
        }
      }
    } catch (e) {
      print('Navidrome auth error: $e');
    }
    _token = null;
    return false;
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List.generate(6, (_) => random.nextInt(256));
    return base64Url.encode(bytes).substring(0, 8);
  }

  Uri _buildUri(String endpoint, {Map<String, String>? extra}) {
    final params = {
      'u': _username!,
      't': _token!,
      's': _salt!,
      'v': '1.16.1',
      'c': 'vinland',
      'f': 'json',
      ...?extra,
    };
    return Uri.parse('$_baseUrl/rest/$endpoint')
        .replace(queryParameters: params);
  }

  Future<List<Track>> fetchAllTracks() async {
    if (!isConnected) return [];
    final albums = await fetchAlbums();
    final List<Track> allTracks = [];

    // Recupere les titres de plusieurs albums en parallele (au lieu d'un
    // aller-retour HTTP sequentiel par album) : divise significativement le
    // temps de resynchro au demarrage sur une bibliotheque de centaines
    // d'albums.
    const batchSize = 8;
    for (var i = 0; i < albums.length; i += batchSize) {
      final batch = albums.skip(i).take(batchSize);
      final results = await Future.wait(batch.map((album) => fetchAlbumTracks(
            album['id'] as String,
            albumArtist: album['artist']?.toString(),
          )));
      for (final tracks in results) {
        allTracks.addAll(tracks);
      }
      print(
          'PROGRESSION: ${(i + batchSize).clamp(0, albums.length)}/${albums.length} albums, ${allTracks.length} tracks');
    }

    print('TOTAL TRACKS: ${allTracks.length}');
    return allTracks;
  }

  Future<List<Map<String, dynamic>>> fetchAlbums() async {
    if (!isConnected) return [];
    final albums = <Map<String, dynamic>>[];
    int offset = 0;
    const int pageSize = 500;

    while (true) {
      try {
        final response = await http
            .get(_buildUri('getAlbumList2.view', extra: {
              'type': 'alphabeticalByName',
              'size': '$pageSize',
              'offset': '$offset',
            }))
            .timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) {
          print('ERREUR LISTE ALBUMS (offset=$offset): ${response.statusCode}');
          break;
        }

        final data = jsonDecode(response.body);
        final albumList =
            data['subsonic-response']?['albumList2']?['album'] as List?;

        if (albumList == null || albumList.isEmpty) break;

        for (final album in albumList) {
          albums.add({
            'id': album['id'],
            'name': album['name'],
            'artist': album['artist'],
            'coverArt': album['coverArt'],
            'songCount': album['songCount'],
            'duration': album['duration'],
            'year': album['year'],
            'genre': album['genre'],
          });
        }

        print(
            'PAGE ALBUMS: offset=$offset, count=${albumList.length}, total=${albums.length}');

        if (albumList.length < pageSize) break;
        offset += pageSize;
      } catch (e) {
        print('fetchAlbums error (offset=$offset): $e');
        break;
      }
    }

    print('TOTAL ALBUMS: ${albums.length}');
    return albums;
  }

  Future<List<Track>> fetchAlbumTracks(String albumId,
      {String? albumArtist}) async {
    if (!isConnected) return [];
    try {
      final response = await http
          .get(_buildUri('getAlbum.view', extra: {'id': albumId}))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final songs =
            data['subsonic-response']?['album']?['song'] as List? ?? [];
        return songs
            .map((json) => _mapSubsonicTrack(json, albumArtist: albumArtist))
            .toList();
      }
    } catch (e) {
      print('fetchAlbumTracks error: $e');
    }
    return [];
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

  String getStreamUrl(String id, {int? maxBitRateKbps, String? format}) {
    if (!isConnected) return '';
    final effectiveBitRate = maxBitRateKbps ?? streamMaxBitRateKbps;
    final effectiveFormat = format ?? 'mp3';
    var url =
        '$_baseUrl/rest/stream.view?id=$id&u=$_username&t=$_token&s=$_salt&v=1.16.1&c=vinland'
        '&maxBitRate=$effectiveBitRate&format=$effectiveFormat';
    return url;
  }

  String getCoverUrl(String id) {
    if (!isConnected) return '';
    return '$_baseUrl/rest/getCoverArt.view?id=$id&u=$_username&t=$_token&s=$_salt&v=1.16.1&c=vinland';
  }

  Track _mapSubsonicTrack(dynamic json, {String? albumArtist}) {
    final id = json['id']?.toString() ?? '';
    final durationSec = json['duration'] ?? 180;
    return Track(
      id: 'navidrome_$id',
      title: json['title']?.toString() ?? 'Inconnu',
      artist: json['artist']?.toString() ?? 'Inconnu',
      album: json['album']?.toString() ?? 'Inconnu',
      duration: Duration(
          seconds: durationSec is int
              ? durationSec
              : int.tryParse(durationSec.toString()) ?? 180),
      filePath: getStreamUrl(id),
      coverPath: getCoverUrl(id),
      isLiked: json['starred'] != null,
      albumId: json['parent']?.toString(),
      albumArtist: albumArtist ?? json['albumArtist']?.toString(),
      year: json['year'] is int
          ? json['year'] as int
          : int.tryParse(json['year']?.toString() ?? ''),
      addedToServerAt: json['created'] != null
          ? DateTime.tryParse(json['created'].toString())
          : null,
    );
  }

  Future<bool> starTrack(String trackId) async {
    if (!isConnected) return false;
    final cleanId = trackId.replaceFirst('navidrome_', '');
    try {
      final response = await http
          .get(
            _buildUri('star.view', extra: {'id': cleanId}),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      print('starTrack error: $e');
      return false;
    }
  }

  Future<bool> unstarTrack(String trackId) async {
    if (!isConnected) return false;
    final cleanId = trackId.replaceFirst('navidrome_', '');
    try {
      final response = await http
          .get(
            _buildUri('unstar.view', extra: {'id': cleanId}),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      print('unstarTrack error: $e');
      return false;
    }
  }

  Future<Map<String, DateTime?>> fetchStarredTrackIds() async {
    if (!isConnected) return {};
    try {
      final response = await http
          .get(_buildUri('getStarred2.view'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final songs =
            data['subsonic-response']?['starred2']?['song'] as List? ?? [];
        return {
          for (var s in songs)
            'navidrome_${s['id']}': s['starred'] != null
                ? DateTime.tryParse(s['starred'].toString())
                : null
        };
      }
    } catch (e) {
      print('fetchStarred error: $e');
    }
    return {};
  }

  Future<bool> starAlbum(String albumId) async {
    if (!isConnected) return false;
    try {
      final response = await http
          .get(_buildUri('star.view', extra: {'albumId': albumId}))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      print('starAlbum error: $e');
      return false;
    }
  }

  Future<bool> unstarAlbum(String albumId) async {
    if (!isConnected) return false;
    try {
      final response = await http
          .get(_buildUri('unstar.view', extra: {'albumId': albumId}))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      print('unstarAlbum error: $e');
      return false;
    }
  }

  Future<Set<String>> fetchStarredAlbumIds() async {
    if (!isConnected) return {};
    try {
      final response = await http
          .get(_buildUri('getStarred2.view'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final albums =
            data['subsonic-response']?['starred2']?['album'] as List? ?? [];
        return albums.map((a) => 'navidrome_${a['id']}').toSet();
      }
    } catch (e) {
      print('fetchStarredAlbumIds error: $e');
    }
    return {};
  }

  /// Playlists visibles pour l'utilisateur connecte : les siennes + celles
  /// que d'autres utilisateurs ont marquees publiques (comportement standard
  /// getPlaylists.view sans parametre "username"). C'est cette liste qui
  /// permet de decouvrir les "amis" (= tout autre "owner" present ici) sans
  /// avoir besoin d'un compte admin.
  Future<List<Map<String, dynamic>>> fetchPlaylists() async {
    if (!isConnected) return [];
    try {
      final response = await http
          .get(_buildUri('getPlaylists.view'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final raw =
            data['subsonic-response']?['playlists']?['playlist'] as List? ??
                [];
        return raw
            .map((pl) => {
                  'id': pl['id']?.toString() ?? '',
                  'name': pl['name']?.toString() ?? '',
                  'owner': pl['owner']?.toString() ?? '',
                  'public': pl['public'] == true,
                  'comment': pl['comment']?.toString() ?? '',
                  'songCount': pl['songCount'] ?? 0,
                })
            .toList();
      }
    } catch (e) {
      print('fetchPlaylists error: $e');
    }
    return [];
  }

  /// Ids (prefixes 'navidrome_', dans l'ordre du serveur) des titres d'une
  /// playlist, qu'elle appartienne a l'utilisateur courant ou (si publique)
  /// a un autre utilisateur.
  Future<List<String>> fetchPlaylistSongIds(String playlistId) async {
    if (!isConnected) return [];
    try {
      final response = await http
          .get(_buildUri('getPlaylist.view', extra: {'id': playlistId}))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final songs =
            data['subsonic-response']?['playlist']?['entry'] as List? ?? [];
        return songs.map((s) => 'navidrome_${s['id']}').toList();
      }
    } catch (e) {
      print('fetchPlaylistSongIds error: $e');
    }
    return [];
  }

  /// Cree une playlist sur le serveur et retourne son id, ou null en cas
  /// d'echec. `comment` sert de marqueur interne stable (ex: identifier la
  /// playlist miroir des likes) puisque le nom, lui, est modifiable par
  /// l'utilisateur.
  Future<String?> createServerPlaylist(String name,
      {String? comment, bool public = false}) async {
    if (!isConnected) return null;
    try {
      final response = await http
          .get(_buildUri('createPlaylist.view', extra: {'name': name}))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final id = data['subsonic-response']?['playlist']?['id']?.toString();
      if (id == null) return null;
      if (comment != null || public) {
        await setPlaylistMeta(id, comment: comment, public: public);
      }
      return id;
    } catch (e) {
      print('createServerPlaylist error: $e');
      return null;
    }
  }

  Future<bool> setPlaylistMeta(String playlistId,
      {String? name, String? comment, bool? public}) async {
    if (!isConnected) return false;
    final extra = {'playlistId': playlistId};
    if (name != null) extra['name'] = name;
    if (comment != null) extra['comment'] = comment;
    if (public != null) extra['public'] = public.toString();
    try {
      final response = await http
          .get(_buildUri('updatePlaylist.view', extra: extra))
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      print('setPlaylistMeta error: $e');
      return false;
    }
  }

  /// Remplace entierement le contenu d'une playlist par `cleanTrackIds`
  /// (sans le prefixe 'navidrome_', dans l'ordre voulu). Utilise
  /// songIndexToRemove + songIdToAdd en un seul appel plutot que de
  /// supprimer/recreer la playlist, pour ne pas perdre son id/son statut
  /// public en cours de route.
  Future<bool> replacePlaylistSongs(
      String playlistId, List<String> cleanTrackIds) async {
    if (!isConnected) return false;
    try {
      final current = await fetchPlaylistSongIds(playlistId);
      final currentClean =
          current.map((id) => id.replaceFirst('navidrome_', '')).toList();
      if (currentClean.join(',') == cleanTrackIds.join(',')) return true;

      final uri = _buildUri('updatePlaylist.view');
      final params = Map<String, String>.from(uri.queryParameters);
      final queryParts = <String>[];
      params.forEach((k, v) => queryParts.add('$k=${Uri.encodeQueryComponent(v)}'));
      queryParts.add('playlistId=${Uri.encodeQueryComponent(playlistId)}');
      for (var i = currentClean.length - 1; i >= 0; i--) {
        queryParts.add('songIndexToRemove=$i');
      }
      for (final id in cleanTrackIds) {
        queryParts.add('songIdToAdd=${Uri.encodeQueryComponent(id)}');
      }
      final fullUri = Uri.parse('$_baseUrl/rest/updatePlaylist.view?${queryParts.join('&')}');
      final response = await http.get(fullUri).timeout(const Duration(seconds: 20));
      return response.statusCode == 200;
    } catch (e) {
      print('replacePlaylistSongs error: $e');
      return false;
    }
  }

  Future<bool> deleteServerPlaylist(String playlistId) async {
    if (!isConnected) return false;
    try {
      final response = await http
          .get(_buildUri('deletePlaylist.view', extra: {'id': playlistId}))
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      print('deleteServerPlaylist error: $e');
      return false;
    }
  }
}
