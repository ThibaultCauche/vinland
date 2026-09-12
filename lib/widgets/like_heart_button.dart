import 'package:flutter/material.dart';

/// Bouton coeur partage (mini-player, liste de titres, ecran lecteur) :
/// tap = like/unlike normal, appui long = Super Like (variante visuelle
/// uniquement -- meme comportement qu'un like, voir Track.superLiked et
/// AppState.toggleSuperLike). Un IconButton normal ne supporte pas
/// onLongPress, d'ou ce widget construit sur InkResponse.
class LikeHeartButton extends StatefulWidget {
  final bool liked;
  final bool superLiked;
  final double size;
  final Color idleColor;
  final Color likedColor;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const LikeHeartButton({
    super.key,
    required this.liked,
    required this.superLiked,
    required this.onTap,
    required this.onLongPress,
    this.size = 20,
    this.idleColor = Colors.white54,
    this.likedColor = const Color(0xFF1DB954),
  });

  @override
  State<LikeHeartButton> createState() => _LikeHeartButtonState();
}

class _LikeHeartButtonState extends State<LikeHeartButton> {
  // Bug connu InkResponse/InkWell : contrairement a un GestureDetector nu,
  // fournir onTap ET onLongPress ne les rend pas mutuellement exclusifs --
  // le relachement du clic qui suit un appui long redeclenche aussi onTap.
  // Sans ce garde-fou, ca annulait le Super Like juste apres l'avoir active
  // (le tap normal qui suivait retirait le like, donc superLiked avec) :
  // c'est ce que les testeurs voyaient comme "ca delike au lieu de
  // superliker".
  bool _justLongPressed = false;

  void _handleLongPress() {
    _justLongPressed = true;
    widget.onLongPress();
  }

  void _handleTap() {
    if (_justLongPressed) {
      _justLongPressed = false;
      return;
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.liked ? widget.likedColor : widget.idleColor;
    return InkResponse(
      onTap: _handleTap,
      onLongPress: _handleLongPress,
      radius: widget.size,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: widget.superLiked
            ? _DoubleHeart(color: color, size: widget.size)
            : Icon(widget.liked ? Icons.favorite : Icons.favorite_border,
                color: color, size: widget.size),
      ),
    );
  }
}

class _DoubleHeart extends StatelessWidget {
  final Color color;
  final double size;

  const _DoubleHeart({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    final double heartSize = size * 0.75;
    return SizedBox(
      width: size + heartSize * 0.4,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.favorite, color: color, size: heartSize),
          Positioned(
            right: 0,
            bottom: 0,
            child: Icon(Icons.favorite, color: color, size: heartSize),
          ),
        ],
      ),
    );
  }
}
