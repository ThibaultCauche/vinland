import 'dart:async';
import 'dart:convert';
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
  String? get baseUrl => _baseUrl;

  Future<bool> loadCredentials() async {
    final creds = await SecureStorage.getCredentials();
    _baseUrl = creds['url'];
    _username = creds['username'];
    _password = creds['password'];

    if (_baseUrl == null || _username == null || _password == null) {
      _baseUrl = kNavidromeUrl;
      _username = kNavidromeUser;
      _password = kNavidromePass;
      await SecureStorage.saveCredentials(_baseUrl!, _username!, _password!);
    }

    if (_baseUrl != null && _username != null && _password != null) {
      return await _authenticate();
    }
    return false;
  }

  Future<bool> saveCredentials(
      String url, String username, String password) async {
    await SecureStorage.saveCredentials(url, username, password);
    _baseUrl = url;
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

    _salt = _generateSalt();
    _token = md5.convert(utf8.encode(_password! + _salt!)).toString();

    final url = Uri.parse(
      '$_baseUrl/rest/ping.view?u=$_username&t=$_token&s=$_salt&v=1.16.1&c=vinland&f=json',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['subsonic-response']?['status'] == 'ok';
      }
    } catch (e) {
      print('Navidrome auth error: $e');
    }
    _token = null;
    return false;
  }

  String _generateSalt() {
    final random = List.generate(6, (_) => DateTime.now().microsecond % 256);
    return base64Url.encode(random).substring(0, 8);
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
    int totalSongs = 0;

    for (int i = 0; i < albums.length; i++) {
      final album = albums[i];
      final tracks = await fetchAlbumTracks(
        album['id'] as String,
        albumArtist: album['artist']?.toString(),
      );
      allTracks.addAll(tracks);
      totalSongs += tracks.length;

      if ((i + 1) % 100 == 0) {
        print(
            'PROGRESSION: ${i + 1}/${albums.length} albums, $totalSongs tracks');
      }
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

  String getStreamUrl(String id) {
    if (!isConnected) return '';
    return '$_baseUrl/rest/stream.view?id=$id&u=$_username&t=$_token&s=$_salt&v=1.16.1&c=vinland';
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

  Future<Set<String>> fetchStarredTrackIds() async {
    if (!isConnected) return {};
    try {
      final response = await http
          .get(
            _buildUri('getStarred2.view'),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final songs =
            data['subsonic-response']?['starred2']?['song'] as List? ?? [];
        return songs.map((s) => 'navidrome_${s['id']}').toSet();
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
}
