import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../desktop/desktop_theme_settings.dart';
import '../providers/app_state.dart';
import '../services/avatar_service.dart';
import '../theme/mobile_theme_settings.dart';
import '../widgets/app_background.dart';
import '../widgets/user_avatar.dart';

/// Photo de profil + theme du fond de l'app (couleur unie / cover floutee /
/// transparent sur Windows) reunis au meme endroit : les deux sont de la
/// personnalisation "comment l'app se presente", contrairement au reste des
/// Parametres qui touche a la bibliotheque/au compte/au comportement.
class PersonalizationScreen extends StatefulWidget {
  const PersonalizationScreen({super.key});

  @override
  State<PersonalizationScreen> createState() => _PersonalizationScreenState();
}

class _PersonalizationScreenState extends State<PersonalizationScreen> {
  bool _uploading = false;

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null || !mounted) return;

    setState(() => _uploading = true);
    final ok = await context.read<AppState>().uploadMyAvatar(File(path));
    if (!mounted) return;
    setState(() => _uploading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Photo de profil mise a jour'
            : "Echec de l'envoi -- verifie ta connexion et reessaie."),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = defaultTargetPlatform == TargetPlatform.windows;
    final avatarConfigured = AvatarService().isConfigured;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Personnalisation',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: PlatformBackground(
        child: Consumer<AppState>(
          builder: (context, state, child) {
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                Center(
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          UserAvatar(
                            username: state.userName ?? '?',
                            size: 96,
                            cacheBust: state.avatarVersion,
                          ),
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: Material(
                              color: const Color(0xFF1DB954),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _uploading ? null : _pickAvatar,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: _uploading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.edit,
                                          color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(state.userName ?? '',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      if (!avatarConfigured) ...[
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            "Service de photo de profil pas encore configure -- "
                            'contacte l\'administrateur du serveur.',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 32, 16, 8),
                  child: Text('FOND DE L\'APP',
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1)),
                ),
                if (isDesktop)
                  const DesktopThemeSettingsSection()
                else
                  const MobileThemeSettingsSection(),
                const SizedBox(height: 40),
              ],
            );
          },
        ),
      ),
    );
  }
}
