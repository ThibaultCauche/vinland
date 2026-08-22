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
    if (text.isEmpty) return '';
    var normalized = text.toLowerCase().trim();
    // Supprimer accents
    normalized = normalized
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('å', 'a')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ø', 'o')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ç', 'c')
        .replaceAll('ñ', 'n')
        .replaceAll('æ', 'ae')
        .replaceAll('œ', 'oe')
        .replaceAll('ß', 'ss');
    // Caractères spéciaux → espaces
    normalized = normalized.replaceAll(RegExp(r'[^\w\s]'), ' ');
    // Espaces multiples → un seul
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  String _removeStopWords(String text) {
    final stopWords = {
      'the',
      'a',
      'an',
      'and',
      'or',
      'as',
      'at',
      'by',
      'for',
      'in',
      'of',
      'on',
      'to',
      'with',
      'de',
      'la',
      'le',
      'les',
      'et',
      'des',
      'du',
      'un',
      'une',
      'au',
      'aux',
      'en',
      'dans',
      'i',
      'you',
      'he',
      'she',
      'it',
      'we',
      'they',
      'me',
      'my',
      'your',
      'his',
      'her',
      'its',
    };
    return text
        .split(' ')
        .where((w) => w.length > 2 && !stopWords.contains(w))
        .join(' ');
  }

  /// Retire les featuring, parenthèses, suffixes de version
  String _coreTitle(String title) {
    var t = title.toLowerCase().trim();
    // Retirer les parenthèses avec feat/ft/with/prod
    t = t.replaceAll(
        RegExp(r'\s*\(\s*(feat\.?|ft\.?|with|prod\.?|presents?)\s+[^)]*\)',
            caseSensitive: false),
        '');
    t = t.replaceAll(
        RegExp(r'\s*\[\s*(feat\.?|ft\.?|with|prod\.?|presents?)\s+[^\]]*\]',
            caseSensitive: false),
        '');
    // Retirer les suffixes après tiret : versions, remix, etc.
    t = t.replaceAll(
        RegExp(
            r'\s*[-–]\s*(.+remix|remix|edit|version|radio\s*edit|radio\s*mix|live|acoustic|sped\s*up|slowed|reverb|instrumental|cover|demo|bonus\s*track|skit|intro|outro|interlude|theme|from\s+the|from\s+.*soundtrack|motion\s*picture|original\s*score)\s*$',
            caseSensitive: false),
        '');
    // Retirer les versions entre parenthèses à la fin
    t = t.replaceAll(
        RegExp(
            r'\s*\(\s*\d{4}\s*(remaster|re-master|version|edit|mix)?\s*\)\s*$',
            caseSensitive: false),
        '');
    t = t.replaceAll(
        RegExp(
            r'\s*\(\s*(.+remix|remix|edit|version|radio|live|acoustic|sped\s*up|slowed|reverb|instrumental|cover|demo|theme|from)\s*[^)]*\)\s*$',
            caseSensitive: false),
        '');
    // Retirer "feat." / "ft." inline (tout ce qui suit)
    t = t.replaceAll(
        RegExp(r'\s+(feat\.?|ft\.?)\s+.*$', caseSensitive: false), '');

    // Retirer les crochets restants
    t = t.replaceAll(RegExp(r'\s*\[[^\]]*\]'), '');
    // Retirer les parenthèses restantes
    t = t.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
    return _normalize(t);
  }

  /// Normalise un nom d'artiste : retire "the ", séparateurs multiples
  String _coreArtist(String artist) {
    if (artist.isEmpty) return '';
    var a = artist.toLowerCase().trim();
    // Retirer "the " au début
    a = a.replaceAll(RegExp(r'^the\s+'), '');
    // Séparer par ; d'abord (format Spotify), puis & et ,
    final parts =
        a.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';

    // Artistes "génériques" à ignorer comme principal
    final genericNames = {
      'arcane',
      'league of legends',
      'glee cast',
      'k-pop demon hunters cast',
      'cast of epic: the musical',
      'teamfight tactics',
      'riot games',
      'fueled by ramen',
      'warner records',
      'universal music',
      'sony music',
      'atlantic records',
      'columbia',
      'epic',
      'interscope',
      'republic records',
    };

    String primary = parts[0];
    if (genericNames.contains(primary) && parts.length > 1) {
      primary = parts[1];
    }

    // Nettoyer le résultat
    a = primary.replaceAll(RegExp(r'[&+,/]'), ' ');
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

      // ═══ PASS 2 : Core title + core artist (strict) ═══
      if (match == null && byCoreTitle.containsKey(coreTitle)) {
        final candidates = byCoreTitle[coreTitle]!;
        match = candidates.cast<Track?>().firstWhere(
              (c) =>
                  c != null &&
                  _artistsMatchStrict(coreArtist, _coreArtist(c.artist)),
              orElse: () => null,
            );
        if (match != null) {
          confidence = 0.95;
          pass2++;
        }
      }

      // ═══ PASS 3 : Core title seul (si titre assez long / distinctif) ═══
      if (match == null && coreTitle.length > 8) {
        if (byCoreTitle.containsKey(coreTitle)) {
          final candidates = byCoreTitle[coreTitle]!;
          match = candidates.cast<Track?>().firstWhere(
                (c) =>
                    c != null &&
                    _artistsMatchStrict(coreArtist, _coreArtist(c.artist)),
                orElse: () => null,
              );
          if (match != null) {
            confidence = 0.90;
            pass3++;
          }
        }
      }

      // ═══ PASS 4 : Similarité Jaro-Winkler (SANS STOP WORDS) ═══
      if (match == null) {
        final spotClean = _removeStopWords(coreTitle);
        if (spotClean.length > 5) {
          for (final entry in byCoreTitle.entries) {
            final localClean = _removeStopWords(entry.key);
            if (_jaroWinkler(spotClean, localClean) > 0.95) {
              for (final candidate in entry.value) {
                if (_artistsMatchStrict(
                    coreArtist, _coreArtist(candidate.artist))) {
                  match = candidate;
                  confidence = 0.88;
                  pass4++;
                  break;
                }
              }
              if (match != null) break;
            }
          }
        }
      }

      // ═══ PASS 5 : Match par artiste strict + similarité titre très haute ═══
      if (match == null && coreArtist.length > 2) {
        for (final entry in byCoreTitle.entries) {
          for (final candidate in entry.value) {
            final candCoreArtist = _coreArtist(candidate.artist);
            if (!_artistsMatchStrict(coreArtist, candCoreArtist)) continue;

            final candCoreTitle = _coreTitle(candidate.title);
            final sim = _jaroWinkler(
              _removeStopWords(coreTitle),
              _removeStopWords(candCoreTitle),
            );
            if (sim > 0.95) {
              // Anti-préfixe: évite "TAKE ME" → "take me as i am"
              final shorter = coreTitle.length < candCoreTitle.length
                  ? coreTitle
                  : candCoreTitle;
              final longer = coreTitle.length < candCoreTitle.length
                  ? candCoreTitle
                  : coreTitle;
              if (longer.contains(shorter) &&
                  shorter.length < longer.length * 0.8) continue;

              match = candidate;
              confidence = 0.85;
              break;
            }
          }
          if (match != null) break;
        }
      }

      // ═══ FILTRE FINAL : pas de match si confiance trop faible ═══
      if (match != null && confidence < 0.85) {
        match = null;
        confidence = 0;
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
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    if (a.contains(b) || b.contains(a)) {
      final minLen = a.length < b.length ? a.length : b.length;
      if (minLen >= 2) return true;
    }
    final aWords = a.split(' ').where((w) => w.length > 2).toSet();
    final bWords = b.split(' ').where((w) => w.length > 2).toSet();
    if (aWords.isEmpty || bWords.isEmpty) return false;
    final common = aWords.intersection(bWords);
    return common.length >= aWords.length * 0.5 ||
        common.length >= bWords.length * 0.5 ||
        common.length >= 2;
  }

  bool _artistsMatchStrict(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    if (a.contains(b) || b.contains(a)) {
      final minLen = a.length < b.length ? a.length : b.length;
      if (minLen >= 2) return true;
    }
    final aWords = a.split(' ').where((w) => w.length > 1).toSet();
    final bWords = b.split(' ').where((w) => w.length > 1).toSet();
    if (aWords.isEmpty || bWords.isEmpty) return false;
    final common = aWords.intersection(bWords);
    // Au moins 70% des mots en commun
    return common.length >= aWords.length * 0.7 ||
        common.length >= bWords.length * 0.7;
  }

  double _jaroWinkler(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final len1 = s1.length, len2 = s2.length;
    final matchDistance = ((len1 > len2 ? len1 : len2) / 2).floor() - 1;

    final s1Matches = List.filled(len1, false);
    final s2Matches = List.filled(len2, false);

    int matches = 0;
    for (int i = 0; i < len1; i++) {
      final start = (i - matchDistance).clamp(0, len2 - 1);
      final end = (i + matchDistance + 1).clamp(0, len2);
      for (int j = start; j < end; j++) {
        if (s2Matches[j] || s1[i] != s2[j]) continue;
        s1Matches[i] = true;
        s2Matches[j] = true;
        matches++;
        break;
      }
    }

    if (matches == 0) return 0.0;

    int transpositions = 0, k = 0;
    for (int i = 0; i < len1; i++) {
      if (!s1Matches[i]) continue;
      while (!s2Matches[k]) k++;
      if (s1[i] != s2[k]) transpositions++;
      k++;
    }

    final jaro = ((matches / len1) +
            (matches / len2) +
            ((matches - transpositions / 2.0) / matches)) /
        3.0;

    int prefix = 0;
    for (int i = 0; i < (len1 < len2 ? len1 : len2); i++) {
      if (s1[i] == s2[i])
        prefix++;
      else
        break;
      if (prefix >= 4) break;
    }

    return jaro + (prefix * 0.1 * (1 - jaro));
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
