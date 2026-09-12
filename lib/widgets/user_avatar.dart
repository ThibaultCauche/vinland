import 'package:flutter/material.dart';
import '../services/avatar_service.dart';

/// Avatar d'un utilisateur (soi-meme ou un ami) : photo envoyee via
/// AvatarService si disponible, sinon cercle colore avec l'initiale du
/// pseudo -- meme rendu que l'ancien fallback duplique dans chaque ecran
/// (FriendsScreen, FriendProfileScreen, leurs equivalents desktop...),
/// desormais centralise ici.
class UserAvatar extends StatelessWidget {
  final String username;
  final double size;

  /// Change cette valeur (ex: DateTime.now().millisecondsSinceEpoch) pour
  /// forcer le rechargement de l'image apres un nouvel upload : le nom de
  /// fichier cote serveur ne change jamais, donc sans ca un cache HTTP/image
  /// continuerait a montrer l'ancien avatar.
  final Object? cacheBust;

  const UserAvatar({
    super.key,
    required this.username,
    this.size = 40,
    this.cacheBust,
  });

  static const _colors = [
    Color(0xFF1DB954),
    Color(0xFFE91E63),
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFF9C27B0),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _colors[username.hashCode.abs() % _colors.length];
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final fallback = Container(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.4,
        ),
      ),
    );

    final url = AvatarService().avatarUrl(username);
    if (url == null) {
      return SizedBox(width: size, height: size, child: fallback);
    }

    final fullUrl = cacheBust != null ? '$url?v=$cacheBust' : url;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          fullUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => fallback,
        ),
      ),
    );
  }
}
