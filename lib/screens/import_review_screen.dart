import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';

class ImportReviewScreen extends StatefulWidget {
  final List<String> filePaths;

  const ImportReviewScreen({super.key, required this.filePaths});

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  List<Track> _previewTracks = [];
  List<bool> _selected = [];
  bool _isLoading = true;
  int _validCount = 0;
  int _invalidCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _analyzeFiles());
  }

  void _analyzeFiles() async {
    final validExts = {'.mp3', '.flac', '.m4a', '.ogg', '.wav'};
    final tracks = <Track>[];
    int valid = 0;
    int invalid = 0;

    for (final path in widget.filePaths) {
      final ext = path.substring(path.lastIndexOf('.')).toLowerCase();
      if (validExts.contains(ext)) {
        valid++;
        try {
          final track =
              await context.read<AppState>().musicService.parseFile(path);
          tracks.add(track);
        } catch (e) {
          invalid++;
        }
      } else {
        invalid++;
      }
    }

    setState(() {
      _previewTracks = tracks;
      _selected = List.filled(tracks.length, true);
      _validCount = valid;
      _invalidCount = invalid;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selected.where((s) => s).length;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title:
            const Text('Vérification', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_isLoading && selectedCount > 0)
            TextButton(
              onPressed: _importSelected,
              child: Text(
                'Importer ($selectedCount)',
                style: const TextStyle(
                  color: Color(0xFF1DB954),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1DB954)))
          : Column(
              children: [
                _buildStatsCard(),
                if (_previewTracks.isNotEmpty) ...[
                  _buildValidationWarning(),
                  _buildSelectAllBar(selectedCount),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _previewTracks.length,
                      itemBuilder: (context, index) => _buildReviewTile(index),
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

  Widget _buildStatsCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildStatRow(Icons.check_circle, const Color(0xFF1DB954),
              'Fichiers valides', _validCount),
          const SizedBox(height: 8),
          _buildStatRow(
              Icons.error, Colors.red, 'Fichiers ignorés', _invalidCount),
        ],
      ),
    );
  }

  Widget _buildValidationWarning() {
    final suspicious = _previewTracks.where((t) {
      final artistLooksLikeAlbum = t.artist == t.album;
      final artistIsFolderName = t.artist.length < 3 || t.artist.contains('/');
      return artistLooksLikeAlbum || artistIsFolderName;
    }).length;

    if (suspicious == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$suspicious titre(s) ont un artiste suspect (identique à l\'album ou nom de dossier). Vérifiez avant d\'importer.',
              style: const TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectAllBar(int selectedCount) {
    final allSelected = selectedCount == _previewTracks.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            activeColor: const Color(0xFF1DB954),
            onChanged: (v) {
              setState(() {
                _selected = List.filled(_previewTracks.length, v ?? false);
              });
            },
          ),
          const Text(
            'Tout sélectionner',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          const Spacer(),
          Text(
            '$selectedCount / ${_previewTracks.length}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewTile(int index) {
    final track = _previewTracks[index];
    final isSelected = _selected[index];
    final hasIssue = track.artist == track.album || track.artist.length < 3;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: hasIssue
            ? Colors.orange.withOpacity(0.05)
            : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border:
            hasIssue ? Border.all(color: Colors.orange.withOpacity(0.2)) : null,
      ),
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            activeColor: const Color(0xFF1DB954),
            onChanged: (v) {
              setState(() => _selected[index] = v ?? false);
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (hasIssue)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.warning_amber,
                            color: Colors.orange, size: 12),
                      ),
                    Expanded(
                      child: Text(
                        '${track.artist} • ${track.album}',
                        style: TextStyle(
                          color: hasIssue ? Colors.orange : Colors.white54,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white38, size: 18),
            onPressed: () => _editTrack(index),
          ),
        ],
      ),
    );
  }

  void _editTrack(int index) async {
    final track = _previewTracks[index];
    final artistController = TextEditingController(text: track.artist);
    final albumController = TextEditingController(text: track.album);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Modifier les métadonnées',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(track.title,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: artistController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Artiste',
                labelStyle: TextStyle(color: Colors.white54),
                border: UnderlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: albumController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Album',
                labelStyle: TextStyle(color: Colors.white54),
                border: UnderlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _previewTracks[index] = Track(
                  id: track.id,
                  title: track.title,
                  artist: artistController.text.trim(),
                  album: albumController.text.trim(),
                  duration: track.duration,
                  filePath: track.filePath,
                  coverPath: track.coverPath,
                );
              });
              Navigator.pop(context);
            },
            child: const Text('Sauvegarder',
                style: TextStyle(color: Color(0xFF1DB954))),
          ),
        ],
      ),
    );
  }

  void _importSelected() {
    final state = context.read<AppState>();
    final toImport = <Track>[];

    for (var i = 0; i < _previewTracks.length; i++) {
      if (_selected[i]) {
        toImport.add(_previewTracks[i]);
      }
    }

    for (final track in toImport) {
      state.musicService.addTrack(track);
    }

    state.musicService.rebuildAlbums();
    state.musicService.saveToCache();
    state.notifyListeners();

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${toImport.length} titre(s) importé(s)'),
        backgroundColor: const Color(0xFF1DB954),
      ),
    );
  }

  Widget _buildStatRow(IconData icon, Color color, String label, int count) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ),
        Text('$count',
            style: TextStyle(
                color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
