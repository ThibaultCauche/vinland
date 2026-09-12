import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/avatar_config.dart';

/// Client du petit service d'avatars maison (voir avatar-server/ a la racine
/// du repo) : Navidrome n'a aucune notion de photo de profil, ce service la
/// remplace, un fichier par utilisateur. Voir feedback_service.dart pour le
/// meme principe applique au webhook Discord (cle partagee cote config
/// gitignoree, service tiers/maison fait le reste).
class AvatarService {
  static const _contentTypeByExt = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
  };

  bool get isConfigured => kAvatarServiceBaseUrl.isNotEmpty;

  /// URL a laquelle l'avatar de [username] est servi (peut renvoyer 404 si
  /// aucun avatar n'a jamais ete envoye -- a l'appelant de gerer ce cas,
  /// voir UserAvatar qui retombe alors sur les initiales colorees).
  String? avatarUrl(String username) {
    if (!isConfigured) return null;
    return '$kAvatarServiceBaseUrl/avatars/$username';
  }

  Future<bool> uploadAvatar({
    required String username,
    required File file,
  }) async {
    if (!isConfigured) return false;
    final ext = _extensionOf(file.path);
    final contentType = _contentTypeByExt[ext];
    if (contentType == null) return false;

    try {
      final response = await http
          .put(
            Uri.parse('$kAvatarServiceBaseUrl/avatars/$username'),
            headers: {
              'Content-Type': contentType,
              'X-Api-Key': kAvatarServiceApiKey,
            },
            body: await file.readAsBytes(),
          )
          .timeout(const Duration(seconds: 20));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      return false;
    }
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot == -1 ? '' : path.substring(dot).toLowerCase();
  }
}
