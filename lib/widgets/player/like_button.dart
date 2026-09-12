import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../like_heart_button.dart';

class PlayerLikeButton extends StatelessWidget {
  final String trackId;
  const PlayerLikeButton({super.key, required this.trackId});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (bool, bool)>(
      selector: (_, state) =>
          (state.isCurrentTrackLiked, state.isCurrentTrackSuperLiked),
      builder: (context, data, _) {
        final (isLiked, isSuperLiked) = data;
        return LikeHeartButton(
          liked: isLiked,
          superLiked: isSuperLiked,
          size: 24,
          idleColor: Colors.white,
          onTap: () => context.read<AppState>().toggleLike(trackId),
          onLongPress: () =>
              context.read<AppState>().toggleSuperLike(trackId),
        );
      },
    );
  }
}
