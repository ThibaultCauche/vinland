import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) => Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF121212),
          title:
              const Text('Paramètres', style: TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: ListView(
          children: [
            // Mode stockage
            ListTile(
              title: const Text('Mode stockage',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(
                state.isLocalMode ? 'Fichiers locaux' : 'NAS (Navidrome)',
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: Switch(
                value: state.isLocalMode,
                activeColor: const Color(0xFF1DB954),
                onChanged: (v) => state.switchMode(v),
              ),
            ),

            // URL du serveur (visible quand NAS activé)
            if (!state.isLocalMode)
              ListTile(
                title: const Text('URL du serveur',
                    style: TextStyle(color: Colors.white)),
                subtitle: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'https://musique.tondomaine.fr',
                    hintStyle: TextStyle(color: Colors.white38),
                  ),
                  onSubmitted: (url) {
                    // Sauvegarde l'URL
                  },
                ),
              ),

            const Divider(color: Color(0xFF2A2A2A)),

            // Info
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Mode local : musiques stockées sur ce téléphone\n'
                'Mode NAS : streaming depuis ton serveur Navidrome',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
