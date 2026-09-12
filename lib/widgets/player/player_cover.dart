import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../cover_image.dart';

class PlayerCover extends StatelessWidget {
  final String? coverPath;
  const PlayerCover({super.key, this.coverPath});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final exists = context.read<AppState>().coverExists(coverPath);
    final side = MediaQuery.of(context).size.width - 48;

    if (exists && path != null) {
      return Container(
        width: double.infinity,
        height: side,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          image: DecorationImage(
            image: coverImageProvider(context,
                path: path, width: side, height: side),
            fit: BoxFit.cover,
            onError: (_, __) {},
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      height: side,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.album, color: Colors.white54, size: 100),
    );
  }
}
