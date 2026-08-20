import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/discovered_album.dart';
import '../models/discovered_artist.dart';
import '../models/discovered_track.dart';
import '../services/discovery_service.dart';
import '../widgets/track_tile.dart';
import 'album_screen.dart';
import 'discovered_album_screen.dart';

class ArtistScreen extends StatefulWidget {
  final String artistName;

  const ArtistScreen({super.key, required this.artistName});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  final _discovery = DiscoveryService();

  DiscoveredArtist? _discoveredArtist;
  List<DiscoveredAlbum> _discoveredAlbums = [];
  List<DiscoveredTrack> _topTracks = [];
  bool _loadingDeezer = true;
  bool _deepMatching = false;
  int _deepMatchProgress = 0;
  int _deepMatchTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadDeezerData();
  }

  Future<void> _loadDeezerData() async {
    final artists = await _discovery.searchArtists(widget.artistName, limit: 5);
    DiscoveredArtist? match;
    for (final a in artists) {
      if (_normalize(a.name) == _normalize(widget.artistName)) {
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

    if (mounted) setState(() => _loadingDeezer = false);
    _deepMatchAlbums();
  }

  Future<void> _deepMatchAlbums() async {
    final state = context.read<AppState>();
    final allLocalTracks = state.allTracks;

    final localAlbumSignatures = <String, Set<String>>{};
    for (final t in allLocalTracks) {
      if (!_artistContains(t.artist, widget.artistName)) continue;
      final albumKey = _normalize(t.album);
      localAlbumSignatures
          .putIfAbsent(albumKey, () => {})
          .add(_normalize(t.title));
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

    for (final album in unmatched) {
      try {
        final deezerTracks = await _discovery.getAlbumTracks(album.id);
        if (deezerTracks.isEmpty) continue;

        for (final entry in localAlbumSignatures.entries) {
          final localTitles = entry.value;
          if (localTitles.isEmpty) continue;

          int matches = 0;
          for (final dt in deezerTracks) {
            final dtTitle = _normalize(dt.title);
            if (localTitles.any((lt) =>
                lt == dtTitle ||
                lt.contains(dtTitle) ||
                dtTitle.contains(lt))) {
              matches++;
            }
          }

          final ratio = matches / deezerTracks.length;
          final threshold = deezerTracks.length <= 5 ? 0.20 : 0.10;

          if (ratio >= threshold) {
            if (mounted) setState(() => album.isInLibrary = true);
            break;
          }
        }
      } catch (e) {
        print('Deep match error for album ${album.title}: $e');
      }

      if (mounted) setState(() => _deepMatchProgress++);
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (mounted) setState(() => _deepMatching = false);
  }

  /// Vérifie si l'artiste recherché est présent dans le champ artiste (principal ou featuring)
  bool _artistContains(String? artistField, String search) {
    if (artistField == null) return false;
    final s = search.toLowerCase();
    final f = artistField.toLowerCase();
    if (f == s) return true;
    if (f.contains(s)) return true;
    return f.split(RegExp(r'[/&,]')).any((p) => p.trim() == s);
  }

  /// Trouve la track locale correspondant à une track Deezer
  Track? _findLocalTrack(DiscoveredTrack dt, List<Track> candidates) {
    final dtTitle = _normalize(dt.title);
    for (final t in candidates) {
      final ltTitle = _normalize(t.title);
      if (ltTitle == dtTitle) return t;
      if (ltTitle.contains(dtTitle) || dtTitle.contains(ltTitle)) return t;
    }
    return null;
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (List<Track>, List<Album>)>(
      selector: (_, state) {
        bool artistMatch(String? artistField) {
          if (artistField == null) return false;
          final search = widget.artistName.toLowerCase();
          final field = artistField.toLowerCase();
          if (field == search) return true;
          if (field.contains(search)) return true;
          final parts = field.split(RegExp(r'[/&,]'));
          return parts.any((p) => p.trim() == search);
        }

        final tracks =
            state.allTracks.where((t) => artistMatch(t.artist)).toList();
        final albums =
            state.albums.where((a) => artistMatch(a.artist)).toList();
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
        final totalAlbumCount = localAlbums.length + discoveredOnly.length;

        final artistImage = _discoveredArtist?.pictureBigUrl ??
            (localAlbums.isNotEmpty ? localAlbums.first.coverPath : null);

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
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
              // ── HEADER ──
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

              // ── ACTIONS ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          if (allArtistTracks.isNotEmpty) {
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

              // ── TITRES POPULAIRES (depuis Deezer) ──
              if (popularTracks.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Text(
                      'Titres populaires',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                            state.playTrack(popularTracks[index].local!);
                          }
                        },
                      ),
                      childCount: popularTracks.length,
                    ),
                  ),
                ),
              ],

              // ── ALBUMS ──
              if (totalAlbumCount > 0) ...[
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
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF1DB954),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$_deepMatchProgress/$_deepMatchTotal',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12),
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
                        if (index < localAlbums.length) {
                          return _LocalAlbumCard(
                            album: localAlbums[index],
                            state: state,
                            artistName: widget.artistName,
                          );
                        } else {
                          final disc =
                              discoveredOnly[index - localAlbums.length];
                          return _DiscoveredAlbumCard(
                            album: disc,
                            state: state,
                            artistName: widget.artistName,
                          );
                        }
                      },
                      childCount: totalAlbumCount,
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

              // ── TOUS LES TITRES ──
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
                      (context, index) => TrackTile(
                        track: allArtistTracks[index],
                        onTap: () => state.playTrack(allArtistTracks[index]),
                        onLike: () =>
                            state.toggleLike(allArtistTracks[index].id),
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

/// Pair : track Deezer + track locale correspondante (ou null)
class _PopularTrack {
  final DiscoveredTrack discovered;
  final Track? local;
  const _PopularTrack({required this.discovered, this.local});
}

// ── TITRE POPULAIRE ──
class _PopularTrackTile extends StatelessWidget {
  final int index;
  final _PopularTrack track;
  final VoidCallback onPlay;

  const _PopularTrackTile({
    required this.index,
    required this.track,
    required this.onPlay,
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
            // Cover miniature
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(4),
                image: track.discovered.coverUrl != null
                    ? DecorationImage(
                        image: NetworkImage(track.discovered.coverUrl!),
                        fit: BoxFit.cover,
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
              const Icon(Icons.cloud_off, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── CARTE ALBUM LOCAL ──
class _LocalAlbumCard extends StatelessWidget {
  final Album album;
  final AppState state;
  final String artistName;

  const _LocalAlbumCard(
      {required this.album, required this.state, required this.artistName});

  @override
  Widget build(BuildContext context) {
    final albumTracks =
        state.allTracks.where((t) => t.album == album.title).toList();

    return GestureDetector(
      onTap: () => state
          .pushOverlay(AlbumScreen(album: album, filterArtist: artistName)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _AlbumCover(coverPath: album.coverPath),
          ),
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
            '${albumTracks.length} titres',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── CARTE ALBUM DÉCOUVERT (GRISÉ) ──
class _DiscoveredAlbumCard extends StatelessWidget {
  final DiscoveredAlbum album;
  final AppState state;
  final String artistName;

  const _DiscoveredAlbumCard(
      {required this.album, required this.state, required this.artistName});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => state.pushOverlay(
          DiscoveredAlbumScreen(album: album, filterArtist: artistName)),
      child: Opacity(
        opacity: 0.45,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(8),
                  image: album.coverUrl != null
                      ? DecorationImage(
                          image: NetworkImage(album.coverUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: album.coverUrl == null
                    ? const Center(
                        child:
                            Icon(Icons.album, color: Colors.white54, size: 48))
                    : null,
              ),
            ),
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
              album.releaseDate ?? '',
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
  }
}

// ── WIDGETS RÉUTILISABLES ──

class _ArtistAvatar extends StatelessWidget {
  final String? url;
  const _ArtistAvatar({this.url});

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;

    if (imageUrl != null && imageUrl.startsWith('http')) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          image: DecorationImage(
            image: NetworkImage(imageUrl),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    if (imageUrl != null) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          image: DecorationImage(
            image: FileImage(File(imageUrl)),
            fit: BoxFit.cover,
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

    if (path != null && path.startsWith('http')) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
          image: DecorationImage(
            image: NetworkImage(path),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    final exists = context.read<AppState>().coverExists(path);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        image: exists && path != null
            ? DecorationImage(
                image: FileImage(File(path)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: exists != true
          ? const Center(
              child: Icon(Icons.album, color: Colors.white54, size: 48),
            )
          : null,
    );
  }
}
