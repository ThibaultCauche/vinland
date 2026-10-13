import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<void> saveCredentials(
      String url, String username, String password) async {
    await _storage.write(key: 'navidrome_url', value: url);
    await _storage.write(key: 'navidrome_user', value: username);
    await _storage.write(key: 'navidrome_pass', value: password);
  }

  static Future<Map<String, String?>> getCredentials() async {
    return {
      'url': await _storage.read(key: 'navidrome_url'),
      'username': await _storage.read(key: 'navidrome_user'),
      'password': await _storage.read(key: 'navidrome_pass'),
    };
  }

  static Future<void> clear() async => await _storage.deleteAll();

  /// Sel Subsonic fixe des versions <= 1.2.x : le sel est maintenant
  /// regenere a chaque demarrage (voir NavidromeService._newSession), on ne
  /// fait plus que supprimer l'ancien.
  static Future<void> deleteSalt() => _storage.delete(key: 'navidrome_salt');

  /// Cle d'API OpenSubsonic optionnelle (voir NavidromeService.setApiKey).
  static Future<String?> getApiKey() => _storage.read(key: 'navidrome_api_key');

  static Future<void> saveApiKey(String? apiKey) => apiKey == null
      ? _storage.delete(key: 'navidrome_api_key')
      : _storage.write(key: 'navidrome_api_key', value: apiKey);
}
