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
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.read<AppState>().popOverlay(),
          ),
          title:
              const Text('Paramètres', style: TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: ListView(
          children: [
            // Mode stockage (local uniquement pour l'instant)
            ListTile(
              title: const Text('Mode stockage',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Fichiers locaux (NAS désactivé)',
                style: TextStyle(color: Colors.white54),
              ),
              trailing: const Icon(Icons.lock, color: Colors.white38),
            ),

            const Divider(color: Color(0xFF2A2A2A)),

            // Rescan covers (bouton temporaire)
            ListTile(
              leading: const Icon(Icons.image, color: Color(0xFF1DB954)),
              title: const Text('Réextraire les covers',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('À utiliser une seule fois',
                  style: TextStyle(color: Colors.white38)),
              onTap: () async {
                await context.read<AppState>().rescanCoversForExistingTracks();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Covers réextraites'),
                      backgroundColor: Color(0xFF1DB954),
                    ),
                  );
                }
              },
            ),

            const Divider(color: Color(0xFF2A2A2A)),

            // Info
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Vinland v1.0.0\nMode NAS désactivé — sera réactivé après configuration du serveur.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
