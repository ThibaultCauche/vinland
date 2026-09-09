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

  /// Salt Subsonic persiste : reutilise le meme salt entre les sessions pour
  /// que les URLs de stream/cover restent identiques (sinon le cache image
  /// de Flutter ne sert jamais et chaque redemarrage recharge tout a vide).
  static Future<String?> getSalt() => _storage.read(key: 'navidrome_salt');

  static Future<void> saveSalt(String salt) =>
      _storage.write(key: 'navidrome_salt', value: salt);
}
