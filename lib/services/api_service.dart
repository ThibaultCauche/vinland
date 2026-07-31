import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../models/track.dart';
import 'secure_storage.dart';

class ApiService {
  String? _baseUrl;
  String? _username;
  String? _password;
  String? _token;
  bool useLocal = true;

  /// Charge les credentials depuis le stockage sécurisé.
  Future<void> loadCredentials() async {
    final creds = await SecureStorage.getCredentials();
    _baseUrl = creds['url'];
    _username = creds['username'];
    _password = creds['password'];
    if (_baseUrl != null && _username != null && _password != null) {
      await _authenticate();
    }
  }

  bool get hasCredentials =>
      _baseUrl != null &&
      _username != null &&
      _password != null &&
      _token != null;

  void setMode(bool local) => useLocal = local;

  /// Authentifie via l'API Subsonic et récupère un token.
  /// Le mot de passe n'est JAMAIS envoyé en clair.
  Future<void> _authenticate() async {
    if (_baseUrl == null || _username == null || _password == null) return;

    // Subsonic auth: salt + token = md5(password + salt)
    final salt = _generateSalt();
    final token = md5.convert(utf8.encode(_password! + salt)).toString();

    final url = Uri.parse(
      '$_baseUrl/rest/ping.view?u=$_username&t=$token&s=$salt&v=1.16.1&c=vinland&f=json',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final status = data['subsonic-response']?['status'];
        if (status == 'ok') {
          _token = token;
        } else {
          _token = null;
          print(
              'AUTH ERROR: ${data['subsonic-response']?['error']?['message']}');
        }
      }
    } on SocketException catch (e) {
      print('NETWORK ERROR: $e');
      _token = null;
    } on FormatException catch (e) {
      print('PARSE ERROR: $e');
      _token = null;
    }
  }

  String _generateSalt() {
    final random = List<int>.generate(6, (_) => _randomByte());
    return base64Url.encode(random).substring(0, 8);
  }

  int _randomByte() => DateTime.now().microsecond % 256;

  Future<List<Track>> getTracks() async {
    if (useLocal || !hasCredentials) return [];

    try {
      final response = await http
          .get(_buildUri('getSongs.view'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final songs = data['subsonic-response']?['songs'] as List? ?? [];
        return songs.map((json) => _mapSubsonicTrack(json)).toList();
      }
    } on SocketException catch (e) {
      print('NETWORK ERROR getTracks: $e');
    } on FormatException catch (e) {
      print('PARSE ERROR getTracks: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getAlbums() async {
    if (useLocal || !hasCredentials) return [];

    try {
      final response = await http
          .get(_buildUri('getAlbumList2.view',
              extra: {'type': 'alphabeticalByName'}))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final albums =
            data['subsonic-response']?['albumList2']?['album'] as List? ?? [];
        return albums.cast<Map<String, dynamic>>();
      }
    } on SocketException catch (e) {
      print('NETWORK ERROR getAlbums: $e');
    } on FormatException catch (e) {
      print('PARSE ERROR getAlbums: $e');
    }
    return [];
  }

  String getCoverUrl(String id) {
    if (_baseUrl == null || _username == null || _token == null) return '';
    return '$_baseUrl/rest/getCoverArt.view?id=$id&u=$_username&t=$_token&v=1.16.1&c=vinland';
  }

  String getStreamUrl(String id) {
    if (_baseUrl == null || _username == null || _token == null) return '';
    return '$_baseUrl/rest/stream.view?id=$id&u=$_username&t=$_token&v=1.16.1&c=vinland';
  }

  Uri _buildUri(String endpoint, {Map<String, String>? extra}) {
    final params = <String, String>{
      'u': _username!,
      't': _token!,
      'v': '1.16.1',
      'c': 'vinland',
      'f': 'json',
      ...?extra,
    };
    return Uri.parse('$_baseUrl/rest/$endpoint')
        .replace(queryParameters: params);
  }

  Track _mapSubsonicTrack(dynamic json) {
    final id = json['id']?.toString() ?? '';
    return Track(
      id: id,
      title: json['title']?.toString() ?? 'Inconnu',
      artist: json['artist']?.toString() ?? 'Inconnu',
      album: json['album']?.toString() ?? 'Inconnu',
      duration: Duration(seconds: json['duration'] ?? 180),
      filePath: getStreamUrl(id),
      coverPath: null,
    );
  }
}
