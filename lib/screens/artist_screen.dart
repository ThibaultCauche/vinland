import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/discovered_album.dart';
import '../models/discovered_artist.dart';
import '../models/discovered_track.dart';
import '../models/recent_play.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../services/matching_service.dart';
import '../widgets/download_button.dart';
import '../widgets/track_tile.dart';
import '../widgets/cover_image.dart';
import 'album_screen.dart';
import 'discovered_album_screen.dart';

class _ArtistCache {
  final DiscoveredArtist? artist;
  final List<DiscoveredAlbum> albums;
  final List<DiscoveredTrack> topTracks;
  final bool deepMatched;
  _ArtistCache(
      {this.artist,
      required this.albums,
      required this.topTracks,
      this.deepMatched = false});
}

class ArtistScreen extends StatefulWidget {
  final String artistName;

  const ArtistScreen({super.key, required this.artistName});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  static final Map<String, _ArtistCache> _deezerCache = {};
  final _discovery = DiscoveryService();
  final _downloadWorker = DownloadWorkerService();
  final Map<int, DownloadUiState> _downloadStates = {};

  DiscoveredArtist? _discoveredArtist;
  List<DiscoveredAlbum> _discoveredAlbums = [];
  List<DiscoveredTrack> _topTracks = [];
  bool _loadingDeezer = true;
  bool _deepMatching = false;
  bool _loadingTopTracks = true;
  int _deepMatchProgress = 0;
  int _deepMatchTotal = 0;

  // Nombre de titres reel par album Deezer (id -> nb_tracks) : l'endpoint
  // liste des albums d'un artiste ne renvoie pas ce champ (contrairement a
  // /album/{id} ou /search/album), donc on le recupere a part pour ne pas
  // afficher le nombre de titres deja telecharges comme total de l'album.
  final Map<int, int> _trueTrackCounts = {};

  @override
  void initState() {
    super.initState();
    final cached = _deezerCache[MatchingService.normalize(widget.artistName)];
    if (cached != null) {
      _discoveredArtist = cached.artist;
      _discoveredAlbums = cached.albums;
      _topTracks = cached.topTracks;
      _loadingDeezer = false;
      _loadingTopTracks = false;
      if (!cached.deepMatched) _deepMatchAlbums();
      _loadTrueTrackCounts();
    } else {
      _loadDeezerData();
    }
  }

  Future<void> _loadTrueTrackCounts() async {
    final targets = _discoveredAlbums
        .where((a) => a.isInLibrary && !_trueTrackCounts.containsKey(a.id))
        .toList();
    if (targets.isEmpty) return;

    const batchSize = 5;
    for (var i = 0; i < targets.length; i += batchSize) {
      final batch = targets.skip(i).take(batchSize);
      await Future.wait(batch.map((a) async {
        final full = await _discovery.getAlbum(a.id);
        if (full?.nbTracks != null) _trueTrackCounts[a.id] = full!.nbTracks!;
      }));
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadDeezerData() async {
    final artists = await _discovery.searchArtists(widget.artistName, limit: 5);
    DiscoveredArtist? match;
    for (final a in artists) {
      if (MatchingService.artistsMatch(a.name, widget.artistName)) {
        match = a;
        break;
      }
    }

    if (match != null) {
      _discoveredArtist = match;
      final albumsFuture = _discovery.getArtistAlbums(match.id, limit: 50);
      final topFuture = _discovery.getArtistTopTracks(match.id, limit: 5);
      final results = await Future.wait([albumsFuture, topFuture]);
      _discoveredAlbums = results[0] as List<DiscoveredAlbum>;
      _topTracks = results[1] as List<DiscoveredTrack>;
    }

    if (mounted)
      setState(() {
        _loadingDeezer = false;
        _loadingTopTracks = false; // ← ici, APRÈS le Future.wait
      });
    _deezerCache[MatchingService.normalize(widget.artistName)] = _ArtistCache(
      artist: _discoveredArtist,
      albums: _discoveredAlbums,
      topTracks: _topTracks,
    );
    _deepMatchAlbums();
    _loadTrueTrackCounts();
  }

  /// Demande le telechargement automatique d'un titre populaire absent du
  /// NAS (voir DownloadWorkerService) -- meme logique que AlbumScreen,
  /// jusqu'ici jamais branchee sur cette page (retour utilisateur). Pas
  /// besoin de recharger _topTracks apres coup : `popularTracks` (dans
  /// build()) recroise deja _topTracks avec state.allTracks a chaque
  /// reconstruction, donc syncRecentlyAdded() suffit a faire apparaitre le
  /// titre comme disponible.
  Future<void> _downloadTrack(DiscoveredTrack track) async {
    setState(() => _downloadStates[track.id] = DownloadUiState.downloading);

    final jobId = await _downloadWorker.requestDownload(
      artist: track.artistName,
      title: track.title,
      album: track.albumName == 'Inconnu' ? null : track.albumName,
    );
    if (jobId == null) {
      if (mounted) {
        setState(() => _downloadStates[track.id] = DownloadUiState.failed);
      }
      return;
    }

    final status = await _downloadWorker.waitForCompletion(jobId);
    if (!mounted) return;

    if (status.state == DownloadJobState.done) {
      await context.read<AppState>().syncRecentlyAdded();
      if (mounted) setState(() => _downloadStates.remove(track.id));
    } else {
      setState(() => _downloadStates[track.id] = DownloadUiState.failed);
    }
  }

  Future<void> _deepMatchAlbums() async {
    final state = context.read<AppState>();
    final allLocalTracks = state.allTracks;

    final localAlbumSignatures = <String, Set<String>>{};
    for (final t in allLocalTracks) {
      if (!MatchingService.artistsMatch(t.artist, widget.artistName)) continue;
      final albumKey = MatchingService.normalize(t.album);
      localAlbumSignatures.putIfAbsent(albumKey, () => {}).add(t.title);
    }

    final unmatched = _discoveredAlbums.where((a) => !a.isInLibrary).toList();
    if (unmatched.isEmpty) return;

    if (mounted) {
      setState(() {
        _deepMatching = true;
        _deepMatchTotal = unmatched.length;
        _deepMatchProgress = 0;
      });
    }

    // Traite les albums par petits lots en parallele au lieu d'un appel
    // Deezer sequentiel par album : plus rapide, et l'UI (albums grises qui
    // deviennent disponibles) se met a jour progressivement lot par lot
    // plutot qu'en un seul bloc a la toute fin.
    const batchSize = 5;
    for (var i = 0; i < unmatched.length; i += batchSize) {
      final batch = unmatched.skip(i).take(batchSize);

      await Future.wait(batch.map((album) async {
        try {
          final deezerTracks = await _discovery.getAlbumTracks(album.id);
          if (deezerTracks.isEmpty) return;

          for (final entry in localAlbumSignatures.entries) {
            final localTitles = entry.value;
            if (localTitles.isEmpty) continue;

            int matches = 0;
            for (final dt in deezerTracks) {
              if (localTitles
                  .any((lt) => MatchingService.titlesMatch(lt, dt.title))) {
                matches++;
              }
            }

            final ratio = matches / deezerTracks.length;
            final threshold = deezerTracks.length <= 5 ? 0.20 : 0.10;

            if (ratio >= threshold) {
              album.isInLibrary = true;
              break;
            }
          }
        } catch (e) {
          print('Deep match error for album ${album.title}: $e');
        }
      }));

      if (mounted) {
        setState(() => _deepMatchProgress += batch.length);
      }
    }

    if (mounted) {
      setState(() {
        _deepMatching = false;
        final key = MatchingService.normalize(widget.artistName);
        if (_deezerCache.containsKey(key)) {
          _deezerCache[key] = _ArtistCache(
            artist: _discoveredArtist,
            albums: _discoveredAlbums,
            topTracks: _topTracks,
            deepMatched: true,
          );
        }
      });
    }
  }

  /// Trouve la track locale correspondant a une track Deezer
  Track? _findLocalTrack(DiscoveredTrack dt, List<Track> candidates) {
    for (final t in candidates) {
      if (MatchingService.titlesMatch(t.title, dt.title)) return t;
    }
    return null;
  }

  /// Parse une date Deezer ("YYYY-MM-DD" ou juste "YYYY") en DateTime.
  DateTime? _parseReleaseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw) ??
        DateTime.tryParse(RegExp(r'^\d{4}').stringMatch(raw) != null
            ? '${RegExp(r'^\d{4}').stringMatch(raw)}-01-01'
            : '');
  }

  void _recordRecent(AppState state, {String? coverPath}) {
    state.recordRecentPlay(RecentPlay(
      type: RecentPlayType.artist,
      id: widget.artistName,
      title: widget.artistName,
      subtitle: 'Artiste',
      coverPath: coverPath ?? _discoveredArtist?.pictureBigUrl,
      playedAt: DateTime.now(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (List<Track>, List<Album>)>(
      selector: (_, state) {
        bool artistMatch(String? artistField) =>
            MatchingService.artistFieldContains(artistField, widget.artistName);

        final allTracks = state.allTracks;
        final tracks = allTracks.where((t) => artistMatch(t.artist)).toList();

        // Index id -> track construit une seule fois : evite un scan complet
        // de la bibliotheque pour chaque trackId de chaque album ci-dessous.
        final tracksById = {for (final t in allTracks) t.id: t};

        // Inclut les albums dont l'artiste d'album correspond
        // OU dont au moins une track correspond
        final albums = state.albums.where((a) {
          if (artistMatch(a.artist)) return true;
          return a.trackIds.any((id) {
            final track = tracksById[id];
            return track != null && artistMatch(track.artist);
          });
        }).toList();

        return (tracks, albums);
      },
      builder: (context, data, child) {
        final (allArtistTracks, localAlbums) = data;
        final state = context.read<AppState>();

        // Match les top tracks Deezer avec les tracks locales
        final popularTracks = <_PopularTrack>[];
        for (final dt in _topTracks) {
          final local = _findLocalTrack(dt, allArtistTracks);
          popularTracks.add(_PopularTrack(discovered: dt, local: local));
        }

        final discoveredOnly =
            _discoveredAlbums.where((d) => !d.isInLibrary).toList();

        // Album Deezer par titre normalise (pour retrouver, pour un album
        // local partiellement possede, son nombre de titres reel).
        final deezerByTitle = {
          for (final d in _discoveredAlbums)
            MatchingService.normalize(d.title): d
        };

        // Albums locaux + Deezer tries par date de sortie decroissante
        // (les albums sans date connue sont relegues a la fin).
        final sortedAlbumEntries = <_ArtistAlbumEntry>[
          for (final a in localAlbums)
            _ArtistAlbumEntry.local(
              a,
              a.year != null ? DateTime(a.year!) : null,
              knownTotalTrackCount: () {
                final match = deezerByTitle[MatchingService.normalize(a.title)];
                if (match == null) return null;
                return _trueTrackCounts[match.id] ?? match.nbTracks;
              }(),
            ),
          for (final a in discoveredOnly)
            _ArtistAlbumEntry.discovered(a, _parseReleaseDate(a.releaseDate)),
        ]..sort((a, b) {
            final da = a.sortDate;
            final db = b.sortDate;
            if (da == null && db == null) return 0;
            if (da == null) return 1;
            if (db == null) return -1;
            return db.compareTo(da);
          });

        // Separe les singles (1 titre) des albums complets : les afficher
        // dans la meme grille que des albums entiers rendait le rendu
        // bizarre (meme taille de tuile pour 1 titre ou 15).
        final fullAlbumEntries =
            sortedAlbumEntries.where((e) => e.trackCount > 1).toList();
        final singleEntries =
            sortedAlbumEntries.where((e) => e.trackCount <= 1).toList();

        final artistImage = _discoveredArtist?.pictureBigUrl ??
            (localAlbums.isNotEmpty ? localAlbums.first.coverPath : null);

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => state.popOverlay(),
            ),
            title: Text(widget.artistName,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          body: CustomScrollView(
            slivers: [
              // HEADER
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _ArtistAvatar(url: artistImage),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.artistName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${allArtistTracks.length} titres locaux',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 14),
                            ),
                            if (_discoveredAlbums.isNotEmpty)
                              Text(
                                '${_discoveredAlbums.length} albums sur Deezer',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ACTIONS
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          if (allArtistTracks.isNotEmpty) {
                            _recordRecent(state, coverPath: artistImage);
                            state.playTrack(allArtistTracks.first,
                                trackList: allArtistTracks);
                          }
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Lecture'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DB954),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.shuffle, color: Colors.white),
                        onPressed: () {
                          if (allArtistTracks.isNotEmpty) {
                            _recordRecent(state, coverPath: artistImage);
                            final shuffled = List.of(allArtistTracks)
                              ..shuffle();
                            state.playTrack(shuffled.first,
                                trackList: shuffled);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // TITRES POPULAIRES (depuis Deezer)
              if (_loadingTopTracks) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Text('Titres populaires',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _SkeletonPopularTile(index: index),
                      childCount: 5,
                    ),
                  ),
                ),
              ] else if (popularTracks.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Text('Titres populaires',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _PopularTrackTile(
                        index: index,
                        track: popularTracks[index],
                        onPlay: () {
                          if (popularTracks[index].local != null) {
                            _recordRecent(state, coverPath: artistImage);
                            state.playTrack(popularTracks[index].local!);
                          }
                        },
                        downloadState:
                            _downloadStates[popularTracks[index].discovered.id],
                        showDownloadButton: _downloadWorker.isConfigured,
                        onDownloadTap: () =>
                            _downloadTrack(popularTracks[index].discovered),
                      ),
                      childCount: popularTracks.length,
                    ),
                  ),
                ),
              ],

              // ALBUMS
              if (fullAlbumEntries.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Row(
                      children: [
                        const Text(
                          'Albums',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_deepMatching) ...[
                          const SizedBox(width: 12),
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white38,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Vérification $_deepMatchProgress/$_deepMatchTotal',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final entry = fullAlbumEntries[index];
                        if (entry.local != null) {
                          return _LocalAlbumCard(
                            album: entry.local!,
                            state: state,
                            artistName: widget.artistName,
                            totalTrackCount: entry.knownTotalTrackCount,
                          );
                        } else {
                          return _DiscoveredAlbumCard(
                            album: entry.discovered!,
                            state: state,
                            artistName: widget.artistName,
                          );
                        }
                      },
                      childCount: fullAlbumEntries.length,
                    ),
                  ),
                ),
              ] else if (_loadingDeezer) ...[
                const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child:
                          CircularProgressIndicator(color: Color(0xFF1DB954)),
                    ),
                  ),
                ),
              ],

              // SINGLES ET EP (rangee compacte, separee des albums complets)
              if (singleEntries.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Text(
                      'Singles',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 168,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: singleEntries.length,
                      itemBuilder: (context, index) {
                        final entry = singleEntries[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: entry.local != null
                              ? _LocalAlbumCard(
                                  album: entry.local!,
                                  state: state,
                                  artistName: widget.artistName,
                                  totalTrackCount: entry.knownTotalTrackCount,
                                  compact: true,
                                )
                              : _DiscoveredAlbumCard(
                                  album: entry.discovered!,
                                  state: state,
                                  artistName: widget.artistName,
                                  compact: true,
                                ),
                        );
                      },
                    ),
                  ),
                ),
              ],

              // TOUS LES TITRES
              if (allArtistTracks.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Text(
                      'Tous les titres',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Selector<AppState, Track?>(
                        selector: (_, s) => s.currentTrack,
                        builder: (context, currentTrack, __) => TrackTile(
                          track: allArtistTracks[index],
                          isPlaying:
                              currentTrack?.id == allArtistTracks[index].id,
                          onTap: () {
                            _recordRecent(state, coverPath: artistImage);
                            state.playTrack(allArtistTracks[index]);
                          },
                          onLike: () =>
                              state.toggleLike(allArtistTracks[index].id),
                        ),
                      ),
                      childCount: allArtistTracks.length,
                    ),
                  ),
                ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
    );
  }
}

/// Entree unifiee (album local ou Deezer) pour le tri par date de sortie.
class _ArtistAlbumEntry {
  final Album? local;
  final DiscoveredAlbum? discovered;
  final DateTime? sortDate;
  // Nombre de titres reel de l'album (cote Deezer) quand connu, pour un
  // album local qui n'est possede que partiellement -- sans ca la vignette
  // affichait le nombre de titres deja telecharges comme s'il s'agissait du
  // total de l'album.
  final int? knownTotalTrackCount;

  _ArtistAlbumEntry.local(Album album, this.sortDate,
      {this.knownTotalTrackCount})
      : local = album,
        discovered = null;

  _ArtistAlbumEntry.discovered(DiscoveredAlbum album, this.sortDate)
      : local = null,
        discovered = album,
        knownTotalTrackCount = null;

  /// Nombre de titres. Pour un album Deezer sans compte connu, on suppose
  /// que ce n'est pas un single (evite de le releguer a tort dans la rangee
  /// "Singles" faute d'info).
  int get trackCount => local != null
      ? (knownTotalTrackCount ?? local!.trackIds.length)
      : (discovered!.nbTracks ?? 2);
}

/// Pair : track Deezer + track locale correspondante (ou null)
class _PopularTrack {
  final DiscoveredTrack discovered;
  final Track? local;
  const _PopularTrack({required this.discovered, this.local});
}

// TITRE POPULAIRE
class _PopularTrackTile extends StatelessWidget {
  final int index;
  final _PopularTrack track;
  final VoidCallback onPlay;
  final DownloadUiState? downloadState;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;

  const _PopularTrackTile({
    required this.index,
    required this.track,
    required this.onPlay,
    required this.downloadState,
    required this.showDownloadButton,
    required this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAvailable = track.local != null;

    return InkWell(
      onTap: isAvailable ? onPlay : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(4),
                image: track.discovered.coverUrl != null
                    ? DecorationImage(
                        image: coverImageProvider(context,
                            path: track.discovered.coverUrl!,
                            width: 48,
                            height: 48),
                        fit: BoxFit.cover,
                        onError: (_, __) {},
                      )
                    : null,
              ),
              child: track.discovered.coverUrl == null
                  ? const Icon(Icons.music_note, color: Colors.white54)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.discovered.title,
                    style: TextStyle(
                      color: isAvailable ? Colors.white : Colors.white38,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.discovered.albumName,
                    style: TextStyle(
                      color: isAvailable ? Colors.white54 : Colors.white24,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isAvailable)
              const Icon(Icons.play_circle_outline,
                  color: Color(0xFF1DB954), size: 24)
            else
              DownloadStateIcon(
                state: downloadState,
                showDownloadButton: showDownloadButton,
                onDownloadTap: onDownloadTap,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

// CARTE ALBUM LOCAL
class _LocalAlbumCard extends StatelessWidget {
  final Album album;
  final AppState state;
  final String artistName;
  final bool compact;
  // Nombre de titres reel de l'album cote Deezer, quand connu -- affiche a
  // la place du nombre de titres deja telecharges pour un album seulement
  // partiellement possede.
  final int? totalTrackCount;

  const _LocalAlbumCard({
    required this.album,
    required this.state,
    required this.artistName,
    this.compact = false,
    this.totalTrackCount,
  });

  @override
  Widget build(BuildContext context) {
    // album.trackIds est deja le decompte exact de cet album precis (voir
    // MusicService.rebuildAlbums) -- pas besoin de re-derouler par titre,
    // qui pouvait compter les titres d'un autre album partageant le meme
    // nom.
    final trackCount = totalTrackCount ?? album.trackIds.length;

    final cover = compact
        ? SizedBox(
            width: 120,
            height: 120,
            child: _AlbumCover(coverPath: album.coverPath),
          )
        : Expanded(child: _AlbumCover(coverPath: album.coverPath));

    final card = GestureDetector(
      onTap: () => state
          .pushOverlay(AlbumScreen(album: album, filterArtist: artistName)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          cover,
          const SizedBox(height: 8),
          Text(
            album.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            compact ? 'Single' : '$trackCount titres',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );

    return compact ? SizedBox(width: 120, child: card) : card;
  }
}

// CARTE ALBUM DECOUVERT (GRISE)
class _DiscoveredAlbumCard extends StatelessWidget {
  final DiscoveredAlbum album;
  final AppState state;
  final String artistName;
  final bool compact;

  const _DiscoveredAlbumCard({
    required this.album,
    required this.state,
    required this.artistName,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final coverSide = compact ? 120.0 : 150.0;
    final coverBox = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        image: album.coverUrl != null
            ? DecorationImage(
                image: coverImageProvider(context,
                    path: album.coverUrl!, width: coverSide, height: coverSide),
                fit: BoxFit.cover,
                onError: (_, __) {},
              )
            : null,
      ),
      child: album.coverUrl == null
          ? const Center(
              child: Icon(Icons.album, color: Colors.white54, size: 48))
          : null,
    );
    final cover = compact
        ? SizedBox(width: 120, height: 120, child: coverBox)
        : Expanded(child: coverBox);

    final card = GestureDetector(
      onTap: () => state.pushOverlay(
          DiscoveredAlbumScreen(album: album, filterArtist: artistName)),
      child: Opacity(
        opacity: 0.45,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            cover,
            const SizedBox(height: 8),
            Text(
              album.title,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              compact ? 'Single' : (album.releaseDate ?? ''),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, color: Colors.white24, size: 10),
                  SizedBox(width: 4),
                  Text('Non disponible',
                      style: TextStyle(color: Colors.white24, fontSize: 9)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return compact ? SizedBox(width: 120, child: card) : card;
  }
}

// WIDGETS REUTILISABLES

class _ArtistAvatar extends StatelessWidget {
  final String? url;
  const _ArtistAvatar({this.url});

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;

    if (imageUrl != null) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          image: DecorationImage(
            image: coverImageProvider(context,
                path: imageUrl, width: 80, height: 80),
            fit: BoxFit.cover,
            onError: (_, __) {},
          ),
        ),
      );
    }
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF3E3E3E),
        borderRadius: BorderRadius.circular(40),
      ),
      child: const Icon(Icons.person, color: Colors.white54, size: 40),
    );
  }
}

class _AlbumCover extends StatelessWidget {
  final String? coverPath;
  const _AlbumCover({this.coverPath});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;

    final exists = path != null && path.startsWith('http')
        ? true
        : context.read<AppState>().coverExists(path);

    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
          image: exists && path != null
              ? DecorationImage(
                  image: coverImageProvider(context,
                      path: path,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight),
                  fit: BoxFit.cover,
                  onError: (_, __) {},
                )
              : null,
        ),
        child: exists != true
            ? const Center(
                child: Icon(Icons.album, color: Colors.white54, size: 48),
              )
            : null,
      );
    });
  }
}

class _SkeletonPopularTile extends StatelessWidget {
  final int index;
  const _SkeletonPopularTile({required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${index + 1}',
              style: const TextStyle(color: Colors.white24, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 120,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
