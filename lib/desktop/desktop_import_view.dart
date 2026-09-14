import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/local_import_flow.dart';
import 'glass.dart';

/// Onglet dedie a l'import de fichiers locaux (voir runLocalImportFlow,
/// partage avec ImportReviewScreen cote mobile) -- avant, ce n'etait qu'un
/// petit bouton dans l'onglet Bibliotheque, jugé difficile a trouver
/// (retour utilisateur). Meme logique, juste sa propre place dans la nav
/// principale plutot qu'un bouton secondaire.
class DesktopImportView extends StatelessWidget {
  const DesktopImportView({super.key});

  Future<void> _pickAndImport(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'flac', 'm4a', 'ogg', 'wav'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty || !context.mounted) return;
    final files = result.files.map((f) => File(f.path!)).toList();
    await runLocalImportFlow(context, files);
  }

  @override
  Widget build(BuildContext context) {
    // top: DesktopGlass.topInset -- meme raison que les autres vues.
    return Padding(
      padding: const EdgeInsets.only(top: DesktopGlass.topInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Importer des fichiers',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Ajoute des mp3/flac/m4a locaux a ta bibliotheque NAS, puis a une '
            'playlist ou a tes titres likes.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: () => _pickAndImport(context),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    width: 420,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 48),
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(DesktopGlass.radiusLg),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.18), width: 1.5),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.upload_file_rounded,
                            size: 48, color: Colors.white.withOpacity(0.7)),
                        const SizedBox(height: 16),
                        const Text('Choisir des fichiers',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        const Text(
                          'Un ou plusieurs fichiers audio',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
