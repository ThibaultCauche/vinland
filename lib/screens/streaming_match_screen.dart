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
  String? _debugInfo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _performMatching());
  }

  // ── NORMALISATIONS ──

  /// Normalise pour comparaison : minuscule, retire espaces multiples
  String _normalize(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Retire les featuring, parenthèses, suffixes de version
  String _coreTitle(String title) {
    var t = title.toLowerCase();
    // Retire les parenthèses et leur contenu
    t = t.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
    // Retire les crochets et leur contenu
    t = t.replaceAll(RegExp(r'\s*\[[^\]]*\]'), '');
    // Retire les suffixes "- Remastered...", "- Live...", "- Acoustic..."
    t = t.replaceAll(
        RegExp(
            r'\s*[-–]\s*(remaster|live|acoustic|version|edit|mix|radio|instrumental|mono|stereo).*'),
        '');
    // Retire "feat." et ce qui suit
    t = t.replaceAll(RegExp(r'\s*feat\..*'), '');
    // Retire "ft." et ce qui suit
    t = t.replaceAll(RegExp(r'\s*ft\..*'), '');
    return _normalize(t);
  }

  /// Normalise un nom d'artiste : retire "the ", séparateurs multiples
  String _coreArtist(String artist) {
    var a = artist.toLowerCase();
    a = a.replaceAll(RegExp(r'^the\s+'), '');
    a = a.replaceAll(RegExp(r'[&+,]'), ' ');
    return _normalize(a);
  }

  // ── MATCHING ──

  void _performMatching() {
    final state = context.read<AppState>();
    final localTracks = state.allTracks;
    final results = <_MatchResult>[];

    // Index pour recherche rapide
    final byTitle = <String, List<Track>>{};
    final byCoreTitle = <String, List<Track>>{};
    for (final t in localTracks) {
      byTitle.putIfAbsent(_normalize(t.title), () => []).add(t);
      byCoreTitle.putIfAbsent(_coreTitle(t.title), () => []).add(t);
    }

    int pass1 = 0, pass2 = 0, pass3 = 0, pass4 = 0;

    for (final trackData in widget.tracks) {
      final rawTitle = trackData['title'] ?? '';
      final rawArtist = trackData['artist'] ?? '';
      if (rawTitle.isEmpty) continue;

      final normTitle = _normalize(rawTitle);
      final coreTitle = _coreTitle(rawTitle);
      final normArtist = _normalize(rawArtist);
      final coreArtist = _coreArtist(rawArtist);

      Track? match;
      double confidence = 0;

      // ═══ PASS 1 : Exact title + artist ═══
      if (byTitle.containsKey(normTitle)) {
        final candidates = byTitle[normTitle]!;
        match = candidates.cast<Track?>().firstWhere(
              (c) =>
                  c != null && _artistsMatch(normArtist, _normalize(c.artist)),
              orElse: () => null,
            );
        if (match != null) {
          confidence = 1.0;
          pass1++;
        }
      }

      // ═══ PASS 2 : Core title + core artist ═══
      if (match == null && byCoreTitle.containsKey(coreTitle)) {
        final candidates = byCoreTitle[coreTitle]!;
        match = candidates.cast<Track?>().firstWhere(
              (c) =>
                  c != null && _artistsMatch(coreArtist, _coreArtist(c.artist)),
              orElse: () => null,
            );
        if (match != null) {
          confidence = 0.92;
          pass2++;
        }
      }

      // ═══ PASS 3 : Core title seul (si titre assez long / distinctif) ═══
      if (match == null && coreTitle.length > 6) {
        if (byCoreTitle.containsKey(coreTitle)) {
          match = byCoreTitle[coreTitle]!.first;
          confidence = 0.85;
          pass3++;
        }
      }

      // ═══ PASS 4 : Similarité sur les 3 premiers mots ═══
      if (match == null) {
        final spotWords =
            coreTitle.split(' ').where((w) => w.length > 2).take(3).join(' ');
        if (spotWords.length > 6) {
          for (final entry in byCoreTitle.entries) {
            final localWords = entry.key
                .split(' ')
                .where((w) => w.length > 2)
                .take(3)
                .join(' ');
            if (_similarity(spotWords, localWords) > 0.85) {
              // Vérifie l'artiste aussi
              for (final candidate in entry.value) {
                if (_artistsMatch(coreArtist, _coreArtist(candidate.artist))) {
                  match = candidate;
                  confidence = 0.78;
                  pass4++;
                  break;
                }
              }
              if (match != null) break;
            }
          }
        }
      }

      results.add(_MatchResult(
        title: rawTitle,
        artist: rawArtist,
        album: trackData['album'] ?? '',
        dateAdded: _parseDate(trackData['dateAdded']),
        matchedTrack: match,
        confidence: confidence,
      ));
    }

    final matched = results.where((r) => r.matchedTrack != null).length;
    final unmatched = results.length - matched;

    setState(() {
      _matches = results;
      _isLoading = false;
      _debugInfo =
          'P1 exact: $pass1 | P2 core: $pass2 | P3 core solo: $pass3 | P4 fuzzy: $pass4\n'
          'Total: ${results.length} | Match: $matched | Missing: $unmatched';
    });
  }

  bool _artistsMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return true;
    if (a == b) return true;
    // Match si un contient l'autre
    if (a.contains(b) || b.contains(a)) return true;
    // Match par mots : si au moins un mot en commun
    final aWords = a.split(' ').where((w) => w.length > 2).toSet();
    final bWords = b.split(' ').where((w) => w.length > 2).toSet();
    if (aWords.isEmpty || bWords.isEmpty) return true;
    final common = aWords.intersection(bWords);
    return common.length >= aWords.length * 0.4 ||
        common.length >= bWords.length * 0.4;
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
      (i) => List.filled(b.length + 1, 0),
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

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      return DateTime.parse(dateStr);
    } catch (_) {
      return null;
    }
  }

  List<_MatchResult> get _filteredMatches {
    if (_showMissingOnly) {
      return _matches.where((m) => m.matchedTrack == null).toList();
    }
    return _matches;
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
                    color: Color(0xFF1DB954), fontWeight: FontWeight.bold),
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
                  Text('Recherche des correspondances...',
                      style: TextStyle(color: Colors.white54)),
                ],
              ),
            )
          : Column(
              children: [
                // ── DEBUG INFO ──
                if (_debugInfo != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _debugInfo!,
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontFamily: 'monospace'),
                    ),
                  ),
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
                child: _buildStat(Icons.check_circle, const Color(0xFF1DB954),
                    'Correspondances', matched),
              ),
              Container(width: 1, height: 40, color: const Color(0xFF2A2A2A)),
              Expanded(
                child: _buildStat(Icons.help_outline, Colors.orange,
                    'Non trouvés', unmatched),
              ),
            ],
          ),
          if (alreadyLiked > 0) ...[
            const SizedBox(height: 12),
            Text(
              '$alreadyLiked déjà like(s), ${matched - alreadyLiked} à liker',
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
              icon: Icon(Icons.check_circle,
                  color: !_showMissingOnly
                      ? const Color(0xFF1DB954)
                      : Colors.white38,
                  size: 18),
              label: Text('Trouvés ($matched)',
                  style: TextStyle(
                      color: !_showMissingOnly
                          ? const Color(0xFF1DB954)
                          : Colors.white38,
                      fontSize: 13)),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: unmatched > 0
                  ? () => setState(() => _showMissingOnly = true)
                  : null,
              icon: Icon(Icons.warning_amber,
                  color: _showMissingOnly
                      ? Colors.orange
                      : unmatched > 0
                          ? Colors.white54
                          : Colors.white24,
                  size: 18),
              label: Text('Manquants ($unmatched)',
                  style: TextStyle(
                      color: _showMissingOnly
                          ? Colors.orange
                          : unmatched > 0
                              ? Colors.white54
                              : Colors.white24,
                      fontSize: 13)),
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
        Text('$count',
            style: TextStyle(
                color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
            child: Icon(isMatched ? Icons.check : Icons.close,
                color: isMatched ? const Color(0xFF1DB954) : Colors.orange,
                size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(match.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${match.artist} • ${match.album}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (dateStr != null) ...[
                  const SizedBox(height: 4),
                  Text('Ajouté le $dateStr',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11)),
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
                          color: Color(0xFF1DB954), fontSize: 11),
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

    final missing = _matches
        .where((m) => m.matchedTrack == null)
        .map((m) => {'title': m.title, 'artist': m.artist, 'album': m.album})
        .toList();
    state.setMissingTracks(missing);

    Navigator.pop(context);

    final msg = liked > 0
        ? '$liked like(s) ajouté(s), $already déjà présent(s)'
        : '$already titre(s) déjà like(s)';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF1DB954)),
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
