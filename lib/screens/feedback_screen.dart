import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/feedback_service.dart';
import '../widgets/app_background.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  FeedbackType _type = FeedbackType.bug;
  bool _sending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String get _platformLabel {
    if (defaultTargetPlatform == TargetPlatform.android) return 'Android';
    if (defaultTargetPlatform == TargetPlatform.windows) return 'Windows';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'iOS';
    return defaultTargetPlatform.name;
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    if (title.isEmpty || description.isEmpty) return;

    setState(() => _sending = true);
    final state = context.read<AppState>();
    final packageInfo = await PackageInfo.fromPlatform();

    final ok = await FeedbackService().send(
      type: _type,
      title: title,
      description: description,
      username: state.userName ?? 'Inconnu',
      appVersion: packageInfo.version,
      platform: _platformLabel,
    );

    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Merci, ton retour a bien ete envoye !'
            : "Echec de l'envoi -- verifie ta connexion et reessaie."),
      ),
    );
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Un avis, un bug ?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: PlatformBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              "Envoye directement dans le salon Discord de l'app -- "
              'je le vois en temps reel.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            SegmentedButton<FeedbackType>(
              segments: const [
                ButtonSegment(value: FeedbackType.bug, label: Text('Bug')),
                ButtonSegment(value: FeedbackType.idea, label: Text('Idee')),
                ButtonSegment(value: FeedbackType.other, label: Text('Autre')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Titre court',
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              style: const TextStyle(color: Colors.white),
              maxLines: 6,
              decoration: InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _sending ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );
  }
}
