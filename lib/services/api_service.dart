import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/track.dart';
import 'secure_storage.dart';

class ApiService {
  String? _baseUrl;
  String? _username;
  String? _password;
  bool useLocal = true; // ← true = mode local actif, NAS désactivé

  /// Charge les credentials depuis le stockage sécurisé.
  /// Appeler au démarrage de l'app quand le NAS sera configuré.
  Future<void> loadCredentials() async {
    final creds = await SecureStorage.getCredentials();
    _baseUrl = creds['url'];
    _username = creds['username'];
    _password = creds['password'];
  }

  bool get hasCredentials =>
      _baseUrl != null && _username != null && _password != null;

  /// Active/désactive le mode NAS. Pour l'instant, forcer à true (local).
  void setMode(bool local) => useLocal = local;

  Future<List<Track>> getTracks() async {
    if (useLocal || !hasCredentials) return [];

    final response = await http.get(
      Uri.parse(
        '$_baseUrl/rest/getSongs.view?u=$_username&p=$_password&v=1.16.1&c=vinland&f=json',
      ),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final songs = data['subsonic-response']['songs'] as List? ?? [];
      return songs.map((json) => _mapSubsonicTrack(json)).toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getAlbums() async {
    if (useLocal || !hasCredentials) return [];

    final response = await http.get(
      Uri.parse(
        '$_baseUrl/rest/getAlbumList2.view?type=alphabeticalByName&u=$_username&p=$_password&v=1.16.1&c=vinland&f=json',
      ),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final albums =
          data['subsonic-response']['albumList2']['album'] as List? ?? [];
      return albums.cast<Map<String, dynamic>>();
    }
    return [];
  }

  String getCoverUrl(String id) {
    if (_baseUrl == null || _username == null || _password == null) return '';
    return '$_baseUrl/rest/getCoverArt.view?id=$id&u=$_username&p=$_password&v=1.16.1&c=vinland';
  }

  Track _mapSubsonicTrack(dynamic json) {
    return Track(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Inconnu',
      artist: json['artist']?.toString() ?? 'Inconnu',
      album: json['album']?.toString() ?? 'Inconnu',
      duration: Duration(seconds: json['duration'] ?? 180),
      filePath:
          '$_baseUrl/rest/stream.view?id=${json['id']}&u=$_username&p=$_password&v=1.16.1&c=vinland',
    );
  }
}
