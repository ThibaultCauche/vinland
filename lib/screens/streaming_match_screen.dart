import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../models/track.dart';

class StreamingMatchScreen extends StatefulWidget {
  final List<Map<String, String>> tracks;

  const StreamingMatchScreen({super.key, required this.tracks});

  @override
  State<StreamingMatchScreen> createState() => _StreamingMatchScreenState();
}

class _StreamingMatchScreenState extends State<StreamingMatchScreen> {
  List<_MatchResult> _matches = [];
  bool _isLoading = true;
  bool _showMissingOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _performMatching());
  }

  void _performMatching() {
    final state = context.read<AppState>();
    final localTracks = state.allTracks;
    final results = <_MatchResult>[];

    for (final trackData in widget.tracks) {
      final title = _normalize(trackData['title'] ?? '');
      final artist = _normalize(trackData['artist'] ?? '');

      Track? bestMatch;
      double bestScore = 0;

      for (final local in localTracks) {
        final localTitle = _normalize(local.title);
        final localArtist = _normalize(local.artist);

        final exactTitle = title == localTitle;
        final exactArtist = artist == localArtist;
        final titleContains =
            localTitle.contains(title) || title.contains(localTitle);
        final artistContains =
            localArtist.contains(artist) || artist.contains(localArtist);

        double score = 0;
        if (exactTitle && exactArtist) {
          score = 1.0;
        } else if (exactTitle && (artist.isEmpty || artistContains)) {
          score = 0.95;
        } else if (titleContains && (artist.isEmpty || artistContains)) {
          score = 0.85;
        } else {
          final titleSim = _similarity(title, localTitle);
          final artistSim =
              artist.isEmpty ? 1.0 : _similarity(artist, localArtist);
          score = (titleSim * 0.7) + (artistSim * 0.3);
        }

        if (score > bestScore && score > 0.6) {
          bestScore = score;
          bestMatch = local;
        }
      }

      results.add(_MatchResult(
        title: trackData['title']!,
        artist: trackData['artist']!,
        album: trackData['album']!,
        dateAdded: _parseDate(trackData['dateAdded']),
        matchedTrack: bestMatch,
        confidence: bestScore,
      ));
    }

    setState(() {
      _matches = results;
      _isLoading = false;
    });
  }

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      return null;
    }
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1.0;

    final dist = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    return 1.0 - (dist / maxLen);
  }

  int _levenshtein(String a, String b) {
    final matrix = List.generate(
      a.length + 1,
      (i) => List<int>.filled(b.length + 1, 0),
    );

    for (var i = 0; i <= a.length; i++) matrix[i][0] = i;
    for (var j = 0; j <= b.length; j++) matrix[0][j] = j;

    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return matrix[a.length][b.length];
  }

  List<_MatchResult> get _filteredMatches {
    if (_showMissingOnly) {
      return _matches.where((m) => m.matchedTrack == null).toList();
    }
    return _matches.where((m) => m.matchedTrack != null).toList();
  }

  @override
  Widget build(BuildContext context) {
    final matched = _matches.where((m) => m.matchedTrack != null).toList();
    final unmatched = _matches.where((m) => m.matchedTrack == null).toList();
    final alreadyLiked = matched.where((m) => m.matchedTrack!.isLiked).length;
    final newLikes = matched.length - alreadyLiked;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: const Text('Correspondances',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_isLoading && matched.isNotEmpty)
            TextButton(
              onPressed: _likeMatched,
              child: Text(
                newLikes > 0 ? 'Liker $newLikes' : 'Tout liké',
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF1DB954)),
                  SizedBox(height: 16),
                  Text(
                    'Recherche des correspondances...',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                _buildSummary(matched.length, unmatched.length, alreadyLiked),
                _buildFilterBar(matched.length, unmatched.length),
                Expanded(
                  child: _filteredMatches.isEmpty
                      ? Center(
                          child: Text(
                            _showMissingOnly
                                ? 'Aucun titre manquant'
                                : 'Aucune correspondance',
                            style: const TextStyle(color: Colors.white38),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredMatches.length,
                          itemBuilder: (context, index) =>
                              _buildMatchTile(_filteredMatches[index]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummary(int matched, int unmatched, int alreadyLiked) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStat(
                  Icons.check_circle,
                  const Color(0xFF1DB954),
                  'Correspondances',
                  matched,
                ),
              ),
              Container(width: 1, height: 40, color: const Color(0xFF2A2A2A)),
              Expanded(
                child: _buildStat(
                  Icons.help_outline,
                  Colors.orange,
                  'Non trouves',
                  unmatched,
                ),
              ),
            ],
          ),
          if (alreadyLiked > 0) ...[
            const SizedBox(height: 12),
            Text(
              '$alreadyLiked deja like(s), ${matched - alreadyLiked} a liker',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
          if (unmatched > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$unmatched titre(s) non trouve(s). Importez ces fichiers.',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterBar(int matched, int unmatched) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () => setState(() => _showMissingOnly = false),
              icon: Icon(
                Icons.check_circle,
                color: !_showMissingOnly
                    ? const Color(0xFF1DB954)
                    : Colors.white38,
                size: 18,
              ),
              label: Text(
                'Trouves ($matched)',
                style: TextStyle(
                  color: !_showMissingOnly
                      ? const Color(0xFF1DB954)
                      : Colors.white38,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: unmatched > 0
                  ? () => setState(() => _showMissingOnly = true)
                  : null,
              icon: Icon(
                Icons.warning_amber,
                color: _showMissingOnly
                    ? Colors.orange
                    : unmatched > 0
                        ? Colors.white54
                        : Colors.white24,
                size: 18,
              ),
              label: Text(
                'Manquants ($unmatched)',
                style: TextStyle(
                  color: _showMissingOnly
                      ? Colors.orange
                      : unmatched > 0
                          ? Colors.white54
                          : Colors.white24,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(IconData icon, Color color, String label, int count) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildMatchTile(_MatchResult match) {
    final isMatched = match.matchedTrack != null;
    final confidence = (match.confidence * 100).toInt();
    final dateStr = match.dateAdded != null
        ? DateFormat('dd/MM/yyyy').format(match.dateAdded!)
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMatched ? const Color(0xFF1E1E1E) : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: isMatched
            ? Border.all(color: const Color(0xFF1DB954).withOpacity(0.3))
            : Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isMatched
                  ? const Color(0xFF1DB954).withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isMatched ? Icons.check : Icons.close,
              color: isMatched ? const Color(0xFF1DB954) : Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${match.artist} • ${match.album}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (dateStr != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ajoute le $dateStr',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (isMatched) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1DB954).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '→ ${match.matchedTrack!.title} (${match.matchedTrack!.artist}) • $confidence%',
                      style: const TextStyle(
                        color: Color(0xFF1DB954),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _likeMatched() {
    final state = context.read<AppState>();
    int liked = 0;
    int already = 0;

    for (final match in _matches) {
      if (match.matchedTrack != null) {
        if (match.matchedTrack!.isLiked) {
          already++;
        } else {
          if (match.dateAdded != null) {
            final index = state.allTracks
                .indexWhere((t) => t.id == match.matchedTrack!.id);
            if (index != -1) {
              state.allTracks[index].dateAdded = match.dateAdded;
            }
          }
          state.toggleLike(match.matchedTrack!.id);
          liked++;
        }
      }
    }

    state.musicService.saveToCache();

    // Sauvegarde les manquants dans l'app state pour y acceder plus tard
    final missing = _matches
        .where((m) => m.matchedTrack == null)
        .map((m) => {'title': m.title, 'artist': m.artist, 'album': m.album})
        .toList();
    state.setMissingTracks(missing);

    Navigator.pop(context);

    final msg = liked > 0
        ? '$liked like(s) ajoute(s), $already deja present(s)'
        : '$already titre(s) deja like(s)';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1DB954),
      ),
    );
  }
}

class _MatchResult {
  final String title;
  final String artist;
  final String album;
  final DateTime? dateAdded;
  final Track? matchedTrack;
  final double confidence;

  _MatchResult({
    required this.title,
    required this.artist,
    required this.album,
    this.dateAdded,
    this.matchedTrack,
    required this.confidence,
  });
}
