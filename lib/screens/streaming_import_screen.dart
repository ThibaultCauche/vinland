import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/streaming_import_service.dart';
import 'streaming_match_screen.dart';

class StreamingImportScreen extends StatefulWidget {
  const StreamingImportScreen({super.key});

  @override
  State<StreamingImportScreen> createState() => _StreamingImportScreenState();
}

class _StreamingImportScreenState extends State<StreamingImportScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: const Text('Importer depuis un service',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle('1. Plateformes supportees'),
          const SizedBox(height: 8),
          _buildPlatformCard(
            icon: Icons.music_note,
            title: 'Spotify',
            subtitle: 'Export CSV via Exportify',
            color: const Color(0xFF1DB954),
          ),
          _buildPlatformCard(
            icon: Icons.play_circle_fill,
            title: 'YouTube Music',
            subtitle: 'Export JSON via Google Takeout',
            color: Colors.red,
          ),
          _buildPlatformCard(
            icon: Icons.audiotrack,
            title: 'Deezer / Tidal / Apple Music',
            subtitle: 'Export CSV via SongShift ou outils tiers',
            color: Colors.orange,
          ),
          _buildPlatformCard(
            icon: Icons.format_list_bulleted,
            title: 'Autre service',
            subtitle: 'Utilisez notre template CSV universel',
            color: Colors.blue,
          ),
          const SizedBox(height: 32),
          _buildSectionTitle('2. Selectionner votre fichier'),
          const SizedBox(height: 8),
          _buildPlatformCard(
            icon: Icons.cloud_upload,
            title: 'Choisir un fichier',
            subtitle: 'JSON ou CSV depuis n\'importe quel service',
            onTap: _pickFile,
          ),
          const SizedBox(height: 32),
          _buildSectionTitle('3. Pas d\'export ? Utilisez le template'),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF2A2A2A)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Si votre service ne propose pas d\'export, '
                    'remplissez ce template CSV :',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121212),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2A2A2A)),
                    ),
                    child: SelectableText(
                      StreamingImportService.csvTemplate,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _downloadTemplate,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Telecharger le template'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1DB954),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          _buildSectionTitle('4. Formats acceptes'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFormatChip('.json (Spotify, YouTube Music)'),
              _buildFormatChip('.csv (universel)'),
              _buildFormatChip('.txt (CSV brut)'),
            ],
          ),
          if (_isLoading) ...[
            const SizedBox(height: 32),
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF1DB954)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildPlatformCard({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? color,
    VoidCallback? onTap,
  }) {
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (color ?? const Color(0xFF1DB954)).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color ?? const Color(0xFF1DB954),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormatChip(String label) {
    return Chip(
      backgroundColor: const Color(0xFF2A2A2A),
      side: const BorderSide(color: Color(0xFF3E3E3E)),
      label: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'csv', 'txt'],
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path!;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImportProgressScreen(filePath: path),
        ),
      );
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/vinland_template.csv');
      await file.writeAsString(StreamingImportService.csvTemplate);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Template sauvegarde dans : ${file.path}'),
            backgroundColor: const Color(0xFF1DB954),
          ),
        );
      }
    } catch (e) {
      _showError('Erreur lors du telechargement : $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// ===================== ECRAN DE PROGRESSION =====================

class ImportProgressScreen extends StatefulWidget {
  final String filePath;

  const ImportProgressScreen({super.key, required this.filePath});

  @override
  State<ImportProgressScreen> createState() => _ImportProgressScreenState();
}

class _ImportProgressScreenState extends State<ImportProgressScreen> {
  int _parsedCount = 0;
  bool _isDone = false;
  List<Map<String, String>> _tracks = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _startParsing();
  }

  Future<void> _startParsing() async {
    try {
      final ext = widget.filePath
          .substring(widget.filePath.lastIndexOf('.'))
          .toLowerCase();

      if (ext == '.csv' || ext == '.txt') {
        await for (final track
            in StreamingImportService.parseCsvStream(widget.filePath)) {
          if (!mounted) return;
          setState(() {
            _tracks.add(track);
            _parsedCount++;
          });
          // Laisse l'UI respirer toutes les 50 lignes
          if (_parsedCount % 50 == 0) {
            await Future.delayed(const Duration(milliseconds: 1));
          }
        }
      } else {
        // JSON : pas de stream possible, on fait par chunks
        _tracks = await StreamingImportService.parseJsonFile(widget.filePath);
        _parsedCount = _tracks.length;
      }

      if (mounted) {
        setState(() => _isDone = true);
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted && _tracks.isNotEmpty) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => StreamingMatchScreen(tracks: _tracks),
            ),
          );
        } else if (mounted) {
          _error = 'Aucun titre trouve dans le fichier.';
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Erreur : $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: const Text('Analyse en cours...',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_error != null) ...[
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 24),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retour'),
              ),
            ] else ...[
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  color: const Color(0xFF1DB954),
                  strokeWidth: 8,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '$_parsedCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'titres analyses',
                style: const TextStyle(color: Colors.white54, fontSize: 16),
              ),
              if (_isDone) ...[
                const SizedBox(height: 24),
                const Text(
                  'Redirection...',
                  style: TextStyle(color: Color(0xFF1DB954), fontSize: 14),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
