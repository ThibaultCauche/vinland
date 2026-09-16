import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../services/matching_service.dart';
import '../widgets/app_background.dart';
import '../widgets/app_bar_safe_area.dart';

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
  bool _showDuplicatesOnly = false;
  String? _debugInfo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _performMatching());
  }

  // ── MATCHING ──
  // La normalisation et le matching flou (accents, feat/remix, Jaro-Winkler)
  // vivent desormais dans MatchingService, partages avec DiscoveryService et
  // les pages album/artiste pour que le resultat soit coherent partout dans
  // l'app.

  void _performMatching() {
    final state = context.read<AppState>();
    final localTracks = state.allTracks;
    final results = <_MatchResult>[];

    // Index pour recherche rapide
    final byTitle = <String, List<Track>>{};
    final byCoreTitle = <String, List<Track>>{};
    for (final t in localTracks) {
      final nt = MatchingService.normalize(t.title);
      final ct = MatchingService.coreTitle(t.title);
      byTitle.putIfAbsent(nt, () => []).add(t);
      byCoreTitle.putIfAbsent(ct, () => []).add(t);
    }

    int pass1 = 0, pass2 = 0, pass3 = 0, pass4 = 0, pass6 = 0;

    for (final trackData in widget.tracks) {
      final rawTitle = trackData['title'] ?? '';
      final rawArtist = trackData['artist'] ?? '';
      if (rawTitle.isEmpty) continue;

      final normTitle = MatchingService.normalize(rawTitle);
      final coreTitle = MatchingService.coreTitle(rawTitle);
      final normArtist = MatchingService.normalize(rawArtist);
      final coreArtist = MatchingService.coreArtist(rawArtist);

      Track? match;
      double confidence = 0;

      // ═══ PASS 1 : Exact title + artist ═══
      if (byTitle.containsKey(normTitle)) {
        final candidates = byTitle[normTitle]!;
        match = candidates.cast<Track?>().firstWhere(
              (c) =>
                  c != null &&
                  MatchingService.artistsMatch(
                      normArtist, MatchingService.normalize(c.artist)),
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
                  MatchingService.artistsMatch(
                      coreArtist, MatchingService.coreArtist(c.artist),
                      strict: true),
              orElse: () => null,
            );
        if (match != null) {
          confidence = 0.95;
          pass2++;
        }
      }

      // ═══ PASS 3 : Core title exact + artiste strict ═══
      if (match == null && coreTitle.isNotEmpty) {
        if (byCoreTitle.containsKey(coreTitle)) {
          final candidates = byCoreTitle[coreTitle]!;
          match = candidates.cast<Track?>().firstWhere(
                (c) =>
                    c != null &&
                    MatchingService.coreArtist(c.artist) == coreArtist,
                orElse: () => null,
              );
          if (match != null) {
            confidence = 0.92;
            pass3++;
          }
        }
      }

      // ═══ PASS 4 : Similarité Jaro-Winkler (pré-filtré par longueur) ═══
      if (match == null) {
        final spotClean = MatchingService.removeStopWords(coreTitle);
        if (spotClean.length > 5) {
          final spotLen = spotClean.length;
          for (final entry in byCoreTitle.entries) {
            final localClean = MatchingService.removeStopWords(entry.key);
            // Skip si longueur trop différente
            final localLen = localClean.length;
            if (localLen < spotLen * 0.6 || localLen > spotLen * 1.4) continue;
            if (MatchingService.jaroWinkler(spotClean, localClean) > 0.95) {
              for (final candidate in entry.value) {
                if (MatchingService.artistsMatch(
                    coreArtist, MatchingService.coreArtist(candidate.artist),
                    strict: true)) {
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
            final candCoreArtist = MatchingService.coreArtist(candidate.artist);
            if (!MatchingService.artistsMatch(coreArtist, candCoreArtist,
                strict: true)) continue;

            final candCoreTitle = MatchingService.coreTitle(candidate.title);
            final sim = MatchingService.jaroWinkler(
              MatchingService.removeStopWords(coreTitle),
              MatchingService.removeStopWords(candCoreTitle),
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

      // ═══ PASS 6 : Fallback par titre normalisé exact (sans artiste) ═══
      if (match == null && normTitle.isNotEmpty) {
        if (byTitle.containsKey(normTitle)) {
          final candidates = byTitle[normTitle]!;
          if (candidates.length == 1) {
            match = candidates.first;
            confidence = 0.80;
            pass6++;
          }
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
          'P1 exact: $pass1 | P2 core: $pass2 | P3 core strict: $pass3 | P4 fuzzy: $pass4 | P6 title only: $pass6\n'
          'Total: ${results.length} | Match: $matched | Missing: $unmatched';
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

  List<_MatchResult> get _filteredMatches {
    if (_showMissingOnly) {
      return _matches.where((m) => m.matchedTrack == null).toList();
    }
    if (_showDuplicatesOnly) {
      final idCounts = <String, int>{};
      for (final m in _matches.where((m) => m.matchedTrack != null)) {
        idCounts[m.matchedTrack!.id] = (idCounts[m.matchedTrack!.id] ?? 0) + 1;
      }
      final dupIds =
          idCounts.entries.where((e) => e.value > 1).map((e) => e.key).toSet();
      return _matches
          .where((m) =>
              m.matchedTrack != null && dupIds.contains(m.matchedTrack!.id))
          .toList();
    }
    return _matches;
  }

  @override
  Widget build(BuildContext context) {
    final matched = _matches.where((m) => m.matchedTrack != null).toList();
    final unmatched = _matches.where((m) => m.matchedTrack == null).toList();

    final idCounts = <String, int>{};
    for (final m in matched) {
      idCounts[m.matchedTrack!.id] = (idCounts[m.matchedTrack!.id] ?? 0) + 1;
    }
    final duplicateIds =
        idCounts.entries.where((e) => e.value > 1).map((e) => e.key).toSet();
    final duplicates = matched
        .where((m) => duplicateIds.contains(m.matchedTrack!.id))
        .toList();

    final appState = context.read<AppState>();
    final uniqueMatchedIds = matched.map((m) => m.matchedTrack!.id).toSet();
    final alreadyLiked = uniqueMatchedIds.where((id) {
      final t = appState.allTracks
          .cast<Track?>()
          .firstWhere((t) => t?.id == id, orElse: () => null);
      return t != null && t.isLiked;
    }).length;
    final newLikes = uniqueMatchedIds.length - alreadyLiked;

    return Scaffold(
      backgroundColor: Colors.transparent,
      // extendBodyBehindAppBar : voir le commentaire equivalent dans
      // settings_screen.dart (fond identique sur toute la page).
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Correspondances',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_isLoading && matched.isNotEmpty)
            TextButton(
              onPressed: _likeMatched,
              child: Text(
                newLikes > 0 ? 'Liker $newLikes' : 'Tout liker',
                style: const TextStyle(
                    color: Color(0xFF1DB954), fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: PlatformBackground(
        child: Padding(
          padding: EdgeInsets.only(top: appBarSafeTopPadding(context)),
          child: _isLoading
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
                    _buildSummary(matched.length, unmatched.length,
                        alreadyLiked, duplicates.length),
                    _buildFilterBar(
                        matched.length, unmatched.length, duplicates.length),
                    Expanded(
                      child: _filteredMatches.isEmpty
                          ? Center(
                              child: Text(
                                _showMissingOnly
                                    ? 'Aucun titre manquant'
                                    : _showDuplicatesOnly
                                        ? 'Aucun doublon'
                                        : 'Aucune correspondance',
                                style: const TextStyle(color: Colors.white38),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _filteredMatches.length,
                              itemBuilder: (context, index) => _buildMatchTile(
                                  _filteredMatches[index],
                                  duplicateIds.contains(_filteredMatches[index]
                                      .matchedTrack
                                      ?.id)),
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSummary(
      int matched, int unmatched, int alreadyLiked, int duplicatesCount) {
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
              Container(width: 1, height: 40, color: const Color(0xFF2A2A2A)),
              Expanded(
                child: _buildStat(Icons.content_copy, Colors.blue, 'Doublons',
                    duplicatesCount),
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

  Widget _buildFilterBar(int matched, int unmatched, int duplicatesCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () => setState(() {
                _showMissingOnly = false;
                _showDuplicatesOnly = false;
              }),
              icon: Icon(Icons.check_circle,
                  color: !_showMissingOnly && !_showDuplicatesOnly
                      ? const Color(0xFF1DB954)
                      : Colors.white38,
                  size: 18),
              label: Text('Trouvés ($matched)',
                  style: TextStyle(
                      color: !_showMissingOnly && !_showDuplicatesOnly
                          ? const Color(0xFF1DB954)
                          : Colors.white38,
                      fontSize: 12)),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: unmatched > 0
                  ? () => setState(() {
                        _showMissingOnly = true;
                        _showDuplicatesOnly = false;
                      })
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
                      fontSize: 12)),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: duplicatesCount > 0
                  ? () => setState(() {
                        _showMissingOnly = false;
                        _showDuplicatesOnly = true;
                      })
                  : null,
              icon: Icon(Icons.content_copy,
                  color: _showDuplicatesOnly
                      ? Colors.blue
                      : duplicatesCount > 0
                          ? Colors.white54
                          : Colors.white24,
                  size: 18),
              label: Text('Doublons ($duplicatesCount)',
                  style: TextStyle(
                      color: _showDuplicatesOnly
                          ? Colors.blue
                          : duplicatesCount > 0
                              ? Colors.white54
                              : Colors.white24,
                      fontSize: 12)),
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

  Widget _buildMatchTile(_MatchResult match, bool isDuplicate) {
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
            ? isDuplicate
                ? Border.all(color: Colors.blue.withOpacity(0.3))
                : Border.all(color: const Color(0xFF1DB954).withOpacity(0.3))
            : Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isMatched
                  ? isDuplicate
                      ? Colors.blue.withOpacity(0.1)
                      : const Color(0xFF1DB954).withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
                isMatched
                    ? isDuplicate
                        ? Icons.content_copy
                        : Icons.check
                    : Icons.close,
                color: isMatched
                    ? isDuplicate
                        ? Colors.blue
                        : const Color(0xFF1DB954)
                    : Colors.orange,
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
                      color: isDuplicate
                          ? Colors.blue.withOpacity(0.1)
                          : const Color(0xFF1DB954).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '→ ${match.matchedTrack!.title} (${match.matchedTrack!.artist}) • $confidence%',
                      style: TextStyle(
                          color: isDuplicate
                              ? Colors.blue
                              : const Color(0xFF1DB954),
                          fontSize: 11),
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

  Future<void> _likeMatched() async {
    debugPrint('=== _likeMatched called ===');
    final state = context.read<AppState>();
    debugPrint('tracks count: ${state.allTracks.length}');

    if (state.allTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bibliothèque vide — impossible de liker'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    int liked = 0;
    int already = 0;
    int duplicates = 0;
    final Set<String> processedIds = {};
    final List<Future<void>> toggleFutures = [];
    final missing = <Map<String, dynamic>>[];

    // La page "Titres likes" trie par date d'ajout (plus recent d'abord). On
    // pose ici une date synthetique strictement decroissante, une par ligne
    // du CSV (ligne 0 = la plus recente), plutot que de se fier a la colonne
    // "date d'ajout" du fichier : elle est souvent absente, ou n'a qu'une
    // precision a la journee -- ce qui cree des ex-aequo et melange l'ordre
    // affiche. Ca garantit que l'ordre de la liste correspond exactement a
    // l'ordre du fichier importe, y compris pour les titres manquants
    // (intercales via la meme date, voir AppState.likedTracksWithMissing).
    final importBase = DateTime.now();

    for (var i = 0; i < _matches.length; i++) {
      final match = _matches[i];
      final importDate = importBase.subtract(Duration(milliseconds: i));

      if (match.matchedTrack == null) {
        missing.add({
          'title': match.title,
          'artist': match.artist,
          'album': match.album,
          'dateAdded': importDate.toIso8601String(),
        });
        continue;
      }

      final trackId = match.matchedTrack!.id;
      if (processedIds.contains(trackId)) {
        duplicates++;
        continue;
      }
      processedIds.add(trackId);

      if (match.matchedTrack!.isLiked) {
        already++;
      } else {
        final trackIndex =
            state.musicService.allTracks.indexWhere((t) => t.id == trackId);
        if (trackIndex == -1) continue;
        state.musicService.allTracks[trackIndex].dateAdded = importDate;
        toggleFutures.add(state.toggleLike(trackId));
        liked++;
      }
    }

    await Future.wait(toggleFutures);
    await state.musicService.saveToCache();

    state.addMissingTracks(missing);

    if (mounted) {
      final appState = context.read<AppState>();
      Navigator.of(context).popUntil((route) => route.isFirst);
      appState.setTab(1);
      final msg = liked > 0
          ? '$liked like(s) ajouté(s), $already déjà présent(s), $duplicates doublon(s)'
          : '$already titre(s) déjà like(s), $duplicates doublon(s)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: const Color(0xFF1DB954)),
      );
    }
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
