import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';

class PlayerLikeButton extends StatelessWidget {
  final String trackId;
  const PlayerLikeButton({super.key, required this.trackId});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, bool>(
      selector: (_, state) => state.isCurrentTrackLiked,
      builder: (context, isLiked, _) => IconButton(
        icon: Icon(
          isLiked ? Icons.favorite : Icons.favorite_border,
          color: isLiked ? const Color(0xFF1DB954) : Colors.white,
        ),
        onPressed: () => context.read<AppState>().toggleLike(trackId),
      ),
    );
  }
}
