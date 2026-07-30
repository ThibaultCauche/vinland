import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/track.dart';

class ApiService {
  // Change cette URL quand ton NAS sera prêt
  static const String baseUrl =
      'https://musique.tondomaine.fr'; // ou IP locale : 'http://192.168.1.50:4533'

  // Navidrome API (Subsonic compatible)
  static const String username = 'ton_user';
  static const String password = 'ton_pass';

  // Mode local vs NAS
  bool useLocal = true; // ← true = fichiers sur téléphone, false = NAS

  void setMode(bool local) => useLocal = local;

  Future<List<Track>> getTracks() async {
    if (useLocal) return []; // Géré par MusicService en local

    // Appel API Navidrome
    final response = await http.get(
      Uri.parse(
          '$baseUrl/rest/getSongs.view?u=$username&p=$password&v=1.16.1&c=vinland&f=json'),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['subsonic-response']['songs'] as List)
          .map((json) => Track(
                id: json['id'],
                title: json['title'],
                artist: json['artist'],
                album: json['album'],
                duration: Duration(seconds: json['duration'] ?? 180),
                filePath:
                    '$baseUrl/rest/stream.view?id=${json['id']}&u=$username&p=$password&v=1.16.1&c=vinland',
              ))
          .toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getAlbums() async {
    if (useLocal) return [];

    final response = await http.get(
      Uri.parse(
          '$baseUrl/rest/getAlbumList2.view?type=alphabeticalByName&u=$username&p=$password&v=1.16.1&c=vinland&f=json'),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['subsonic-response']['albumList2']['album'] as List)
          .cast<Map<String, dynamic>>();
    }
    return [];
  }

  String getCoverUrl(String id) {
    return '$baseUrl/rest/getCoverArt.view?id=$id&u=$username&p=$password&v=1.16.1&c=vinland';
  }
}
