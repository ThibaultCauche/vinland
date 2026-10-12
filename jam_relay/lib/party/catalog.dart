// Acces en lecture seule au catalogue Navidrome pour les invites (voir
// docs/soiree-protocole.md, « Securite »). Les invites n'ont pas de compte :
// le relais cherche pour eux avec son propre compte, et ne leur renvoie que
// des infos d'affichage (jamais d'URL, d'identifiant ni de jeton).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'party.dart';

class CoverImage {
  final Uint8List bytes;
  final String contentType;
  const CoverImage(this.bytes, this.contentType);
}

/// Identifiants qu'un futur hote presente a `party_create` : jeton Subsonic
/// (md5 du mot de passe + sel) ou cle d'API, jamais le mot de passe.
class HostAuth {
  final String user;
  final String? token;
  final String? salt;
  final String? apiKey;

  const HostAuth({required this.user, this.token, this.salt, this.apiKey});

  static HostAuth? fromJson(Object? json) {
    if (json is! Map) return null;
    final user = json['u'];
    if (user is! String || user.isEmpty) return null;
    final token = json['t'], salt = json['s'], apiKey = json['apiKey'];
    if (apiKey is String && apiKey.isNotEmpty) {
      return HostAuth(user: user, apiKey: apiKey);
    }
    if (token is String && salt is String && token.isNotEmpty) {
      return HostAuth(user: user, token: token, salt: salt);
    }
    return null;
  }
}

abstract class PartyCatalog {
  Future<List<PartySong>> search(String query, {int limit = 20});
  Future<PartySong?> song(String songId);
  Future<CoverImage?> cover(String coverId, int size);

  /// Vrai si Navidrome accepte ces identifiants (appel `ping`).
  Future<bool> verifyHost(HostAuth auth);
}

/// Les ids Navidrome sont alphanumeriques (avec - et _). On refuse le reste
/// avant tout appel, par prudence.
final _safeId = RegExp(r'^[A-Za-z0-9_.-]{1,100}$');

bool isSafeCatalogId(String id) => _safeId.hasMatch(id);

class NavidromeCatalog implements PartyCatalog {
  final Uri baseUrl;
  final String _user;
  final String _password;
  final HttpClient _http;
  final Duration timeout;

  NavidromeCatalog({
    required String baseUrl,
    required String user,
    required String password,
    HttpClient? http,
    this.timeout = const Duration(seconds: 8),
  })  : baseUrl = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _user = user,
        _password = password,
        _http = http ?? HttpClient();

  /// Parametres d'authentification du compte du relais : nouveau sel a
  /// chaque appel, comme le recommande l'API Subsonic.
  Map<String, String> _ownAuth() {
    final random = Random.secure();
    final salt =
        List.generate(12, (_) => random.nextInt(16).toRadixString(16)).join();
    return {
      'u': _user,
      't': md5.convert(utf8.encode(_password + salt)).toString(),
      's': salt,
    };
  }

  Uri _uri(String endpoint, Map<String, String> params,
          Map<String, String> auth) =>
      baseUrl.resolve('rest/$endpoint').replace(queryParameters: {
        ...auth,
        'v': '1.16.1',
        'c': 'vinland-soiree',
        'f': 'json',
        ...params,
      });

  Future<HttpClientResponse> _get(Uri uri) async {
    final request = await _http.getUrl(uri).timeout(timeout);
    return request.close().timeout(timeout);
  }

  Future<Map<String, dynamic>?> _json(
    String endpoint,
    Map<String, String> params, {
    Map<String, String>? auth,
  }) async {
    try {
      final response = await _get(_uri(endpoint, params, auth ?? _ownAuth()));
      final body = await utf8.decodeStream(response).timeout(timeout);
      if (response.statusCode != 200) return null;
      final root = (jsonDecode(body) as Map)['subsonic-response'] as Map?;
      if (root == null || root['status'] != 'ok') return null;
      return root.cast<String, dynamic>();
    } catch (_) {
      // Navidrome injoignable ou reponse bizarre : l'invite recevra une
      // erreur generique, sans details (qui pourraient contenir l'URL).
      return null;
    }
  }

  static PartySong? _toSong(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String) return null;
    String text(String key) => (json[key] ?? '').toString();
    final duration = json['duration'];
    return PartySong(
      songId: id,
      title: text('title'),
      artist: text('artist'),
      album: text('album'),
      durationMs: duration is num ? (duration * 1000).round() : 0,
      coverId: json['coverArt']?.toString(),
    );
  }

  @override
  Future<List<PartySong>> search(String query, {int limit = 20}) async {
    final root = await _json('search3', {
      'query': query,
      'songCount': '$limit',
      'artistCount': '0',
      'albumCount': '0',
    });
    final songs = (root?['searchResult3'] as Map?)?['song'];
    if (songs is! List) return const [];
    return songs.map(_toSong).whereType<PartySong>().toList();
  }

  @override
  Future<PartySong?> song(String songId) async {
    if (!isSafeCatalogId(songId)) return null;
    final root = await _json('getSong', {'id': songId});
    return _toSong(root?['song']);
  }

  @override
  Future<CoverImage?> cover(String coverId, int size) async {
    if (!isSafeCatalogId(coverId)) return null;
    try {
      final response = await _get(
          _uri('getCoverArt', {'id': coverId, 'size': '$size'}, _ownAuth()));
      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add).timeout(timeout);
      final type = response.headers.contentType?.mimeType ?? '';
      // Une erreur Subsonic arrive en JSON/XML avec un statut 200 : ne pas
      // la transmettre comme une image.
      if (response.statusCode != 200 || !type.startsWith('image/')) {
        return null;
      }
      return CoverImage(builder.takeBytes(), type);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> verifyHost(HostAuth auth) async {
    final params = auth.apiKey != null
        ? {'apiKey': auth.apiKey!}
        : {'u': auth.user, 't': auth.token!, 's': auth.salt!};
    final root = await _json('ping', const {}, auth: params);
    return root != null;
  }
}
