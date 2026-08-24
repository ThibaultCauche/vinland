import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';

class PlayerCover extends StatelessWidget {
  final String? coverPath;
  const PlayerCover({super.key, this.coverPath});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final exists = context.read<AppState>().coverExists(coverPath);

    if (exists && path != null) {
      return Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.width - 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          image: DecorationImage(
            image: path.startsWith('http')
                ? NetworkImage(path) as ImageProvider
                : FileImage(File(path)),
            fit: BoxFit.cover,
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
      height: MediaQuery.of(context).size.width - 48,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.album, color: Colors.white54, size: 100),
    );
  }
}
