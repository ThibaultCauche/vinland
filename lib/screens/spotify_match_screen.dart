import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';

class SpotifyMatchScreen extends StatefulWidget {
  final List<Map<String, String>> spotifyTracks;

  const SpotifyMatchScreen({super.key, required this.spotifyTracks});

  @override
  State<SpotifyMatchScreen> createState() => _SpotifyMatchScreenState();
}

class _SpotifyMatchScreenState extends State<SpotifyMatchScreen> {
  List<_MatchResult> _matches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _performMatching());
  }

  void _performMatching() {
    final state = context.read<AppState>();
    final localTracks = state.allTracks;
    final results = <_MatchResult>[];

    for (final spotify in widget.spotifyTracks) {
      final spotifyTitle = _normalize(spotify['title'] ?? '');
      final spotifyArtist = _normalize(spotify['artist'] ?? '');

      Track? bestMatch;
      double bestScore = 0;

      for (final local in localTracks) {
        final titleScore = _similarity(spotifyTitle, _normalize(local.title));
        final artistScore =
            _similarity(spotifyArtist, _normalize(local.artist));
        final score = (titleScore * 0.7) + (artistScore * 0.3);

        if (score > bestScore && score > 0.6) {
          bestScore = score;
          bestMatch = local;
        }
      }

      results.add(_MatchResult(
        spotifyTitle: spotify['title']!,
        spotifyArtist: spotify['artist']!,
        spotifyAlbum: spotify['album']!,
        matchedTrack: bestMatch,
        confidence: bestScore,
      ));
    }

    setState(() {
      _matches = results;
      _isLoading = false;
    });
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

  @override
  Widget build(BuildContext context) {
    final matched = _matches.where((m) => m.matchedTrack != null).length;
    final unmatched = _matches.length - matched;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: const Text('Matching Spotify',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_isLoading && matched > 0)
            TextButton(
              onPressed: _likeMatched,
              child: Text(
                'Liker $matched titres',
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
                _buildSummary(matched, unmatched),
                Expanded(
                  child: ListView.builder(
                    itemCount: _matches.length,
                    itemBuilder: (context, index) =>
                        _buildMatchTile(_matches[index]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummary(int matched, int unmatched) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
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
              'Non trouvés',
              unmatched,
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
                  match.spotifyTitle,
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
                  '${match.spotifyArtist} • ${match.spotifyAlbum}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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

    for (final match in _matches) {
      if (match.matchedTrack != null && !match.matchedTrack!.isLiked) {
        state.toggleLike(match.matchedTrack!.id);
        liked++;
      }
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$liked titre(s) liké(s) depuis Spotify'),
        backgroundColor: const Color(0xFF1DB954),
      ),
    );
  }
}

class _MatchResult {
  final String spotifyTitle;
  final String spotifyArtist;
  final String spotifyAlbum;
  final Track? matchedTrack;
  final double confidence;

  _MatchResult({
    required this.spotifyTitle,
    required this.spotifyArtist,
    required this.spotifyAlbum,
    this.matchedTrack,
    required this.confidence,
  });
}
