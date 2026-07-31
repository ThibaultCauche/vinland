import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class MissingTracksScreen extends StatelessWidget {
  const MissingTracksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        final missing = state.missingTracks;

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => state.popOverlay(),
            ),
            title: const Text(
              'Titres manquants',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              if (missing.isNotEmpty)
                TextButton(
                  onPressed: () => state.clearMissingTracks(),
                  child: const Text(
                    'Effacer',
                    style: TextStyle(color: Color(0xFF1DB954)),
                  ),
                ),
            ],
          ),
          body: missing.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: missing.length,
                  itemBuilder: (context, index) {
                    final track = missing[index];
                    return ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3E3E3E),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.music_off,
                          color: Colors.white54,
                        ),
                      ),
                      title: Text(
                        track['title'] ?? 'Titre inconnu',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        track['artist'] ?? 'Artiste inconnu',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.download,
                        color: Color(0xFF1DB954),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: Color(0xFF1DB954), size: 64),
          SizedBox(height: 16),
          Text(
            'Aucun titre manquant',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Tous vos titres sont disponibles',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
