import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../widgets/track_tile.dart';

class ImportScreen extends StatefulWidget {
  final List<String> filePaths;

  const ImportScreen({super.key, required this.filePaths});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  List<Track> _previewTracks = [];
  bool _isLoading = true;
  int _validCount = 0;
  int _invalidCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _analyzeFiles();
    });
  }

  Future<void> _analyzeFiles() async {
    final validExts = {'.mp3', '.flac', '.m4a', '.ogg', '.wav'};
    final tracks = <Track>[];
    int valid = 0;
    int invalid = 0;

    final musicService = context.read<AppState>().musicService;

    for (final path in widget.filePaths) {
      final ext = path.substring(path.lastIndexOf('.')).toLowerCase();
      if (validExts.contains(ext)) {
        valid++;
        try {
          final track = await musicService.parseFile(path);
          tracks.add(track);
        } catch (e) {
          invalid++;
        }
      } else {
        invalid++;
      }
    }

    if (mounted) {
      setState(() {
        _previewTracks = tracks;
        _validCount = valid;
        _invalidCount = invalid;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title:
            const Text('Vérification', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_previewTracks.isNotEmpty)
            TextButton(
              onPressed: () {
                final state = context.read<AppState>();
                for (final track in _previewTracks) {
                  state.musicService.addTrack(track);
                }
                state.musicService.rebuildAlbums();
                state.musicService.saveToCache();
                state.notifyListeners();

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('${_previewTracks.length} titre(s) importé(s)'),
                    backgroundColor: const Color(0xFF1DB954),
                  ),
                );
              },
              child: const Text(
                'Importer',
                style: TextStyle(
                  color: Color(0xFF1DB954),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1DB954)),
            )
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _buildStatRow(
                        Icons.check_circle,
                        const Color(0xFF1DB954),
                        'Fichiers valides',
                        _validCount,
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow(
                        Icons.error,
                        Colors.red,
                        'Fichiers ignorés',
                        _invalidCount,
                      ),
                    ],
                  ),
                ),
                if (_previewTracks.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Titres à importer',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _previewTracks.length,
                      itemBuilder: (context, index) {
                        final track = _previewTracks[index];
                        return TrackTile(
                          track: track,
                          onTap: () {},
                          onLike: null,
                        );
                      },
                    ),
                  ),
                ],
                if (_previewTracks.isEmpty && !_isLoading)
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Aucun fichier musical trouvé',
                        style: TextStyle(color: Colors.white38, fontSize: 16),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildStatRow(IconData icon, Color color, String label, int count) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
