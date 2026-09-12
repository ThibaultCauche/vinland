import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/discovered_album.dart';
import '../models/discovered_artist.dart';
import '../models/discovered_track.dart';
import '../models/recent_play.dart';
import '../models/track.dart';
import '../services/discovery_service.dart';
import '../widgets/cover_image.dart';
import 'desktop_horizontal_shelf.dart';
import 'desktop_track_row.dart';
import 'glass.dart';
import '../widgets/smooth_scroll.dart';

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

/// Page artiste desktop : equivalent de ArtistScreen (mobile) -- memes
/// donnees (recherche Deezer, top titres, albums grises quand absents du
/// NAS, deep-matching en tache de fond) mais reskin verre depoli et
/// naviguee via la pile locale de DesktopAppShell plutot que les overlays
/// d'AppState.
class DesktopArtistView extends StatefulWidget {
  final String artistName;
  final VoidCallback onBack;
  final void Function(Album album, {String? filterArtist}) onOpenAlbum;
  final void Function(
      {DiscoveredAlbum? album,
      int? albumId,
      String? filterArtist}) onOpenDiscoveredAlbum;

  const DesktopArtistView({
    super.key,
    required this.artistName,
    required this.onBack,
    required this.onOpenAlbum,
    required this.onOpenDiscoveredAlbum,
  });

  @override
  State<DesktopArtistView> createState() => _DesktopArtistViewState();
}

class _DesktopArtistViewState extends State<DesktopArtistView> {
  static final Map<String, _ArtistCache> _deezerCache = {};
  final _discovery = DiscoveryService();

  DiscoveredArtist? _discoveredArtist;
  List<DiscoveredAlbum> _discoveredAlbums = [];
  List<DiscoveredTrack> _topTracks = [];
  bool _loadingDeezer = true;
  bool _loadingTopTracks = true;
  final _scrollController = SmoothScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final cached = _deezerCache[_normalize(widget.artistName)];
    if (cached != null) {
      _discoveredArtist = cached.artist;
      _discoveredAlbums = cached.albums;
      _topTracks = cached.topTracks;
      _loadingDeezer = false;
      _loadingTopTracks = false;
      if (!cached.deepMatched) _deepMatchAlbums();
    } else {
      _loadDeezerData();
    }
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

    if (mounted) {
      setState(() {
        _loadingDeezer = false;
        _loadingTopTracks = false;
      });
    }
    _deezerCache[_normalize(widget.artistName)] = _ArtistCache(
      artist: _discoveredArtist,
      albums: _discoveredAlbums,
      topTracks: _topTracks,
    );
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
              album.isInLibrary = true;
              break;
            }
          }
        } catch (e) {
          debugPrint('Deep match error for album ${album.title}: $e');
        }
      }));

      if (mounted) setState(() {});
    }

    if (mounted) {
      final key = _normalize(widget.artistName);
      if (_deezerCache.containsKey(key)) {
        _deezerCache[key] = _ArtistCache(
          artist: _discoveredArtist,
          albums: _discoveredAlbums,
          topTracks: _topTracks,
          deepMatched: true,
        );
      }
      setState(() {});
    }
  }

  bool _artistContains(String? artistField, String search) {
    if (artistField == null) return false;
    final s = search.toLowerCase();
    final f = artistField.toLowerCase();
    if (f == s) return true;
    if (f.contains(s)) return true;
    return f.split(RegExp(r'[/&,]')).any((p) => p.trim() == s);
  }

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
        bool artistMatch(String? artistField) {
          if (artistField == null) return false;
          final search = widget.artistName.toLowerCase();
          final field = artistField.toLowerCase();
          if (field == search) return true;
          if (field.contains(search)) return true;
          final parts = field.split(RegExp(r'[/&,]'));
          return parts.any((p) => p.trim() == search);
        }

        final allTracks = state.allTracks;
        final tracks = allTracks.where((t) => artistMatch(t.artist)).toList();
        final tracksById = {for (final t in allTracks) t.id: t};
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

        final popularTracks = <_PopularTrack>[];
        for (final dt in _topTracks) {
          final local = _findLocalTrack(dt, allArtistTracks);
          popularTracks.add(_PopularTrack(discovered: dt, local: local));
        }

        final discoveredOnly =
            _discoveredAlbums.where((d) => !d.isInLibrary).toList();

        final sortedAlbumEntries = <_ArtistAlbumEntry>[
          for (final a in localAlbums)
            _ArtistAlbumEntry.local(
                a, a.year != null ? DateTime(a.year!) : null),
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

        final fullAlbumEntries =
            sortedAlbumEntries.where((e) => e.trackCount > 1).toList();
        final singleEntries =
            sortedAlbumEntries.where((e) => e.trackCount <= 1).toList();

        final artistImage = _discoveredArtist?.pictureBigUrl ??
            (localAlbums.isNotEmpty ? localAlbums.first.coverPath : null);

        // topInsetCompact -- meme raison que DesktopCollectionView.
        return Padding(
          padding: const EdgeInsets.only(top: DesktopGlass.topInsetCompact),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GlassIconButton(
                      icon: Icons.arrow_back_rounded, onPressed: widget.onBack),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: _Header(
                        artistName: widget.artistName,
                        artistImage: artistImage,
                        localTrackCount: allArtistTracks.length,
                        deezerAlbumCount: _discoveredAlbums.length,
                        onPlay: allArtistTracks.isEmpty
                            ? null
                            : () {
                                _recordRecent(state, coverPath: artistImage);
                                state.playTrack(allArtistTracks.first,
                                    trackList: allArtistTracks);
                              },
                        onShuffle: allArtistTracks.isEmpty
                            ? null
                            : () {
                                _recordRecent(state, coverPath: artistImage);
                                final shuffled = List.of(allArtistTracks)
                                  ..shuffle();
                                state.playTrack(shuffled.first,
                                    trackList: shuffled);
                              },
                      ),
                    ),
                    if (_loadingTopTracks) ...[
                      const _SectionTitle('Titres populaires'),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => const _SkeletonPopularRow(),
                            childCount: 5,
                          ),
                        ),
                      ),
                    ] else if (popularTracks.isNotEmpty) ...[
                      const _SectionTitle('Titres populaires'),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _PopularTrackRow(
                              index: index,
                              track: popularTracks[index],
                              onPlay: () {
                                if (popularTracks[index].local != null) {
                                  _recordRecent(state, coverPath: artistImage);
                                  state.playTrack(popularTracks[index].local!);
                                }
                              },
                            ),
                            childCount: popularTracks.length,
                          ),
                        ),
                      ),
                    ],
                    if (fullAlbumEntries.isNotEmpty) ...[
                      const _SectionTitle('Albums'),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 170,
                            childAspectRatio: 0.72,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 18,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final entry = fullAlbumEntries[index];
                              if (entry.local != null) {
                                return _LocalAlbumCard(
                                  album: entry.local!,
                                  artistName: widget.artistName,
                                  onTap: () => widget.onOpenAlbum(entry.local!,
                                      filterArtist: widget.artistName),
                                );
                              }
                              return _DiscoveredAlbumCard(
                                album: entry.discovered!,
                                onTap: () => widget.onOpenDiscoveredAlbum(
                                  album: entry.discovered!,
                                  filterArtist: widget.artistName,
                                ),
                              );
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
                            child: CircularProgressIndicator(
                                color: DesktopGlass.accent),
                          ),
                        ),
                      ),
                    ],
                    if (singleEntries.isNotEmpty) ...[
                      const _SectionTitle('Singles'),
                      SliverToBoxAdapter(
                        child: DesktopHorizontalShelf(
                          height: 178,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          itemCount: singleEntries.length,
                          itemBuilder: (context, index) {
                            final entry = singleEntries[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: entry.local != null
                                  ? _LocalAlbumCard(
                                      album: entry.local!,
                                      artistName: widget.artistName,
                                      compact: true,
                                      onTap: () => widget.onOpenAlbum(
                                          entry.local!,
                                          filterArtist: widget.artistName),
                                    )
                                  : _DiscoveredAlbumCard(
                                      album: entry.discovered!,
                                      compact: true,
                                      onTap: () => widget.onOpenDiscoveredAlbum(
                                        album: entry.discovered!,
                                        filterArtist: widget.artistName,
                                      ),
                                    ),
                            );
                          },
                        ),
                      ),
                    ],
                    if (allArtistTracks.isNotEmpty) ...[
                      const _SectionTitle('Tous les titres'),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final track = allArtistTracks[index];
                              return Selector<AppState, Track?>(
                                selector: (_, s) => s.currentTrack,
                                builder: (context, currentTrack, __) =>
                                    DesktopTrackRow(
                                  track: track,
                                  isPlaying: currentTrack?.id == track.id,
                                  onTap: () {
                                    _recordRecent(state,
                                        coverPath: artistImage);
                                    state.playTrack(track,
                                        trackList: allArtistTracks);
                                  },
                                  onLike: () => state.toggleLike(track.id),
                                  onMore: () {},
                                ),
                              );
                            },
                            childCount: allArtistTracks.length,
                          ),
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(
                        child: SizedBox(height: DesktopGlass.playerBarReserve)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ArtistAlbumEntry {
  final Album? local;
  final DiscoveredAlbum? discovered;
  final DateTime? sortDate;

  _ArtistAlbumEntry.local(Album album, this.sortDate)
      : local = album,
        discovered = null;

  _ArtistAlbumEntry.discovered(DiscoveredAlbum album, this.sortDate)
      : local = null,
        discovered = album;

  int get trackCount =>
      local != null ? local!.trackIds.length : (discovered!.nbTracks ?? 2);
}

class _PopularTrack {
  final DiscoveredTrack discovered;
  final Track? local;
  const _PopularTrack({required this.discovered, this.local});
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String artistName;
  final String? artistImage;
  final int localTrackCount;
  final int deezerAlbumCount;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  const _Header({
    required this.artistName,
    required this.artistImage,
    required this.localTrackCount,
    required this.deezerAlbumCount,
    required this.onPlay,
    required this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ArtistAvatar(url: artistImage),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artistName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '$localTrackCount titres locaux'
                  '${deezerAlbumCount > 0 ? ' • $deezerAlbumCount albums sur Deezer' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Material(
                      color: DesktopGlass.accent,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: onPlay,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 20),
                              SizedBox(width: 6),
                              Text('Lecture',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GlassIconButton(icon: Icons.shuffle, onPressed: onShuffle),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PopularTrackRow extends StatelessWidget {
  final int index;
  final _PopularTrack track;
  final VoidCallback onPlay;

  const _PopularTrackRow({
    required this.index,
    required this.track,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final isAvailable = track.local != null;

    return InkWell(
      onTap: isAvailable ? onPlay : null,
      borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text('${index + 1}',
                  style: const TextStyle(color: Colors.white24, fontSize: 14),
                  textAlign: TextAlign.center),
            ),
            const SizedBox(width: 10),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(6),
                image: track.discovered.coverUrl != null
                    ? DecorationImage(
                        image: coverImageProvider(context,
                            path: track.discovered.coverUrl!,
                            width: 44,
                            height: 44),
                        fit: BoxFit.cover,
                        onError: (_, __) {})
                    : null,
              ),
              child: track.discovered.coverUrl == null
                  ? const Icon(Icons.music_note,
                      color: Colors.white54, size: 18)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.discovered.title,
                    style: TextStyle(
                      color: isAvailable ? Colors.white : Colors.white38,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                  color: DesktopGlass.accent, size: 22)
            else
              const Icon(Icons.cloud_off, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }
}

class _SkeletonPopularRow extends StatelessWidget {
  const _SkeletonPopularRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 38),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    width: double.infinity,
                    height: 13,
                    decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 6),
                Container(
                    width: 100,
                    height: 11,
                    decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(2))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalAlbumCard extends StatelessWidget {
  final Album album;
  final String artistName;
  final bool compact;
  final VoidCallback onTap;

  const _LocalAlbumCard({
    required this.album,
    required this.artistName,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final trackCount = album.trackIds.length;

    final cover = compact
        ? SizedBox(
            width: 130,
            height: 130,
            child: _AlbumCover(coverPath: album.coverPath))
        : Expanded(child: _AlbumCover(coverPath: album.coverPath));

    final card = DesktopHoverable(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          cover,
          const SizedBox(height: 8),
          Text(album.title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(compact ? 'Single' : '$trackCount titres',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );

    return compact ? SizedBox(width: 130, child: card) : card;
  }
}

class _DiscoveredAlbumCard extends StatelessWidget {
  final DiscoveredAlbum album;
  final bool compact;
  final VoidCallback onTap;

  const _DiscoveredAlbumCard({
    required this.album,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final double coverSize = compact ? 130 : 180;
    final coverBox = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
        image: album.coverUrl != null
            ? DecorationImage(
                image: coverImageProvider(context,
                    path: album.coverUrl!, width: coverSize, height: coverSize),
                fit: BoxFit.cover,
                onError: (_, __) {})
            : null,
      ),
      child: album.coverUrl == null
          ? const Center(
              child: Icon(Icons.album, color: Colors.white54, size: 40))
          : null,
    );
    final cover = compact
        ? SizedBox(width: 130, height: 130, child: coverBox)
        : Expanded(child: coverBox);

    final card = DesktopHoverable(
      onTap: onTap,
      child: Opacity(
        opacity: 0.45,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            cover,
            const SizedBox(height: 8),
            Text(album.title,
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(compact ? 'Single' : (album.releaseDate ?? ''),
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
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

    return compact ? SizedBox(width: 130, child: card) : card;
  }
}

class _ArtistAvatar extends StatelessWidget {
  final String? url;
  const _ArtistAvatar({this.url});

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    if (imageUrl != null) {
      return Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(48),
          image: DecorationImage(
              image: coverImageProvider(context,
                  path: imageUrl, width: 96, height: 96),
              fit: BoxFit.cover,
              onError: (_, __) {}),
        ),
      );
    }
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: const Color(0xFF3E3E3E),
        borderRadius: BorderRadius.circular(48),
      ),
      child: const Icon(Icons.person, color: Colors.white54, size: 44),
    );
  }
}

class _AlbumCover extends StatelessWidget {
  final String? coverPath;
  const _AlbumCover({this.coverPath});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    return LayoutBuilder(
      builder: (context, constraints) {
        final double side =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 180;
        if (path != null && path.startsWith('http')) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
              image: DecorationImage(
                  image: coverImageProvider(context,
                      path: path, width: side, height: side),
                  fit: BoxFit.cover,
                  onError: (_, __) {}),
            ),
          );
        }
        final exists = context.read<AppState>().coverExists(path);
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
            image: exists && path != null
                ? DecorationImage(
                    image: coverImageProvider(context,
                        path: path, width: side, height: side),
                    fit: BoxFit.cover,
                    onError: (_, __) {})
                : null,
          ),
          child: exists != true
              ? const Center(
                  child: Icon(Icons.album, color: Colors.white54, size: 40))
              : null,
        );
      },
    );
  }
}
