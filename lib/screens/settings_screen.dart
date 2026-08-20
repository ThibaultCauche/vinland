import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.read<AppState>().popOverlay(),
        ),
        title: const Text('Parametres',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Consumer<AppState>(
        builder: (context, state, child) {
          return ListView(
            children: [
              _buildSection('Compte'),
              _buildTile(
                icon: Icons.person,
                title: state.userName ?? 'Utilisateur',
                subtitle: state.userEmail ?? '',
                onTap: () {},
              ),
              _buildSection('Bibliotheque'),
              _buildTile(
                icon: Icons.folder,
                title: 'Importer un dossier',
                subtitle: 'Scanner un dossier de musique',
                onTap: () => _pickFolder(context),
              ),
              _buildSection('Serveur Navidrome'),
              _buildTile(
                icon: Icons.cloud,
                title: 'Configurer Navidrome',
                subtitle: state.useNavidrome ? 'Connecte' : 'Non configure',
                onTap: () => _showNavidromeDialog(context),
              ),
              if (state.useNavidrome) ...[
                _buildTile(
                  icon: Icons.sync,
                  title: 'Synchroniser la bibliotheque',
                  subtitle: 'Mettre a jour depuis le serveur',
                  onTap: () async {
                    await state.syncNavidrome();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Synchronisation terminee')),
                    );
                  },
                ),
                _buildTile(
                  icon: state.useNavidrome
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  title: 'Mode Navidrome',
                  subtitle: state.useNavidrome ? 'Actif' : 'Inactif',
                  onTap: () => state.setNavidromeMode(!state.useNavidrome),
                ),
              ],
              _buildTile(
                icon: Icons.refresh,
                title: 'Rescanner les covers',
                subtitle: 'Re-extrait les pochettes des fichiers existants',
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await state.rescanCoversForExistingTracks();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Rescan des covers termine')),
                  );
                },
              ),
              _buildTile(
                icon: Icons.storage,
                title: 'Stockage',
                subtitle:
                    '${state.allTracks.length} titres, ${state.albums.length} albums',
                onTap: () {},
              ),
              _buildSection('Lecture'),
              _buildSwitchTile(
                icon: Icons.shuffle,
                title: 'Lecture aleatoire',
                value: false,
                onChanged: (v) {},
              ),
              _buildSwitchTile(
                icon: Icons.repeat,
                title: 'Repetition',
                value: false,
                onChanged: (v) {},
              ),
              _buildSection('Qualite'),
              _buildTile(
                icon: Icons.high_quality,
                title: 'Qualite audio',
                subtitle: 'Haute qualite (320kbps)',
                onTap: () {},
              ),
              _buildSection('A propos'),
              _buildTile(
                icon: Icons.info,
                title: 'Vinland v1.0.0',
                subtitle: 'Application de musique locale',
                onTap: () {},
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ElevatedButton(
                  onPressed: () => state.logout(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text('Se deconnecter',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickFolder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<AppState>();
    // Note: FilePicker n'a pas de getDirectoryPath sur iOS, mais fonctionne sur Android/Desktop
    // Tu peux utiliser file_picker ou permission_handler selon ta cible
    messenger.showSnackBar(
      const SnackBar(content: Text('Fonctionnalite a implementer')),
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white54),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: Colors.white54),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF1DB954),
    );
  }

  void _showNavidromeDialog(BuildContext context) {
    final urlCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Navidrome', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'URL (ex: http://100.x.x.x:30043)',
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: userCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Utilisateur',
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Mot de passe',
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              final state = context.read<AppState>();
              final ok = await state.configureNavidrome(
                urlCtrl.text.trim(),
                userCtrl.text.trim(),
                passCtrl.text.trim(),
              );
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text(ok ? 'Connecte a Navidrome' : 'Echec de connexion'),
                ),
              );
            },
            child: const Text('Connecter',
                style: TextStyle(color: Color(0xFF1DB954))),
          ),
        ],
      ),
    );
  }
}
