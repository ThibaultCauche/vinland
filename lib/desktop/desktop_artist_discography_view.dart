import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/discovered_album.dart';
import '../models/discovered_artist.dart';
import '../models/track.dart';
import '../services/artist_discography.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/download_button.dart';
import '../widgets/smooth_scroll.dart';
import 'desktop_track_row.dart';
import 'glass.dart';

/// Page discographie complete d'un artiste desktop : tous ses albums/singles
/// (locaux + Deezer) avec leur tracklist entiere affichee en ligne -- la
/// page artiste elle-meme ne montre plus qu'une rangee d'albums pour rester
/// legere (retour utilisateur : trop de contenu d'un coup rendait la page
/// artiste lourde a charger).
class DesktopArtistDiscographyView extends StatefulWidget {
  final String artistName;
  final void Function(Album album, {String? filterArtist}) onOpenAlbum;
  final void Function(
      {DiscoveredAlbum? album,
      int? albumId,
      String? filterArtist}) onOpenDiscoveredAlbum;

  const DesktopArtistDiscographyView({
    super.key,
    required this.artistName,
    required this.onOpenAlbum,
    required this.onOpenDiscoveredAlbum,
  });

  @override
  State<DesktopArtistDiscographyView> createState() =>
      _DesktopArtistDiscographyViewState();
}

class _DesktopArtistDiscographyViewState
    extends State<DesktopArtistDiscographyView> {
  final _discovery = DiscoveryService();
  final _downloadWorker = DownloadWorkerService();
  final _scrollController = SmoothScrollController();
  final Map<int, DownloadUiState> _downloadStates = {};

  DiscoveredArtist? _discoveredArtist;
  List<ArtistAlbumEntry> _entries = [];
  final Map<int, List<ReleaseTrack>> _tracksByEntry = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final data = await loadArtistDeezerData(_discovery, widget.artistName);
    final localAlbums =
        albumsForArtist(state.albums, state.allTracks, widget.artistName);

    await deepMatchArtistAlbums(
      discovery: _discovery,
      discoveredAlbums: data.albums,
      allLocalTracks: state.allTracks,
      artistName: widget.artistName,
    );

    final trueTrackCounts = <int, int>{};
    final withKnownCount = data.albums.where((a) => a.isInLibrary).toList();
    await Future.wait(withKnownCount.map((a) async {
      final full = await _discovery.getAlbum(a.id);
      if (full?.nbTracks != null) trueTrackCounts[a.id] = full!.nbTracks!;
    }));

    final entries = buildArtistAlbumEntries(
      localAlbums: localAlbums,
      discoveredAlbums: data.albums,
      trueTrackCounts: trueTrackCounts,
    );

    if (!mounted) return;
    setState(() {
      _discoveredArtist = data.artist;
      _entries = entries;
      _loading = false;
    });

    const batchSize = 4;
    final allLocalTracks = state.allTracks;
    for (var i = 0; i < entries.length; i += batchSize) {
      final end =
          (i + batchSize < entries.length) ? i + batchSize : entries.length;
      final indices = [for (var k = i; k < end; k++) k];
      final results = await Future.wait(indices.map((idx) => loadReleaseTracks(
            discovery: _discovery,
            entry: entries[idx],
            discoveredAlbums: data.albums,
            allLocalTracks: allLocalTracks,
          )));
      if (!mounted) return;
      setState(() {
        for (var k = 0; k < indices.length; k++) {
          _tracksByEntry[indices[k]] = results[k];
        }
      });
    }
  }

  Future<void> _downloadTrack(ReleaseTrack rt) async {
    final dt = rt.discovered;
    if (dt == null) return;
    setState(() => _downloadStates[dt.id] = DownloadUiState.downloading);

    final jobId = await _downloadWorker.requestDownload(
      artist: dt.artistName,
      title: dt.title,
      album: dt.albumName == 'Inconnu' ? null : dt.albumName,
    );
    if (jobId == null) {
      if (mounted) setState(() => _downloadStates[dt.id] = DownloadUiState.failed);
      return;
    }

    final status = await _downloadWorker.waitForCompletion(jobId);
    if (!mounted) return;

    if (status.state == DownloadJobState.done) {
      await context.read<AppState>().syncRecentlyAdded();
      if (mounted) setState(() => _downloadStates.remove(dt.id));
    } else {
      setState(() => _downloadStates[dt.id] = DownloadUiState.failed);
    }
  }

  String? _coverPath(ArtistAlbumEntry entry) =>
      entry.local?.coverPath ?? entry.discovered?.coverBigUrl ?? entry.discovered?.coverUrl;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();

    return Padding(
      padding: const EdgeInsets.only(top: DesktopGlass.topInsetCompact),
      child: _loading
          ? const Center(
              child: CircularProgressIndicator(color: DesktopGlass.accent))
          : CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
                    child: Row(
                      children: [
                        if (_discoveredArtist?.pictureBigUrl != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image(
                              image: coverImageProvider(context,
                                  path: _discoveredArtist!.pictureBigUrl!,
                                  width: 56,
                                  height: 56),
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 16),
                        ],
                        Expanded(
                          child: Text('Discographie · ${widget.artistName}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
                for (var i = 0; i < _entries.length; i++) ...[
                  SliverToBoxAdapter(
                    child: _ReleaseHeader(
                      entry: _entries[i],
                      coverPath: _coverPath(_entries[i]),
                      onTap: () {
                        final entry = _entries[i];
                        if (entry.local != null) {
                          widget.onOpenAlbum(entry.local!,
                              filterArtist: widget.artistName);
                        } else {
                          widget.onOpenDiscoveredAlbum(
                            album: entry.discovered!,
                            filterArtist: widget.artistName,
                          );
                        }
                      },
                      onPlay: () {
                        final tracks = _tracksByEntry[i]
                                ?.where((t) => t.local != null)
                                .map((t) => t.local!)
                                .toList() ??
                            const <Track>[];
                        if (tracks.isNotEmpty) {
                          state.playTrack(tracks.first, trackList: tracks);
                        }
                      },
                    ),
                  ),
                  if (_tracksByEntry[i] == null)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white38),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, trackIndex) {
                          final rt = _tracksByEntry[i]![trackIndex];
                          return Selector<AppState, Track?>(
                            selector: (_, s) => s.currentTrack,
                            builder: (context, currentTrack, __) {
                              if (rt.local != null) {
                                return DesktopTrackRow(
                                  track: rt.local!,
                                  isPlaying: currentTrack?.id == rt.local!.id,
                                  onTap: () {
                                    final localTracks = _tracksByEntry[i]!
                                        .where((t) => t.local != null)
                                        .map((t) => t.local!)
                                        .toList();
                                    state.playTrack(rt.local!,
                                        trackList: localTracks);
                                  },
                                  onLike: () =>
                                      state.toggleLike(rt.local!.id),
                                  onMore: () {},
                                );
                              }
                              return _MissingReleaseTrackRow(
                                track: rt,
                                downloadState: rt.discovered != null
                                    ? _downloadStates[rt.discovered!.id]
                                    : null,
                                showDownloadButton:
                                    _downloadWorker.isConfigured,
                                onDownloadTap: () => _downloadTrack(rt),
                              );
                            },
                          );
                        },
                        childCount: _tracksByEntry[i]!.length,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                ],
                const SliverToBoxAdapter(
                    child: SizedBox(height: DesktopGlass.playerBarReserve)),
              ],
            ),
    );
  }
}

class _ReleaseHeader extends StatelessWidget {
  final ArtistAlbumEntry entry;
  final String? coverPath;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  const _ReleaseHeader({
    required this.entry,
    required this.coverPath,
    required this.onTap,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final title = entry.local?.title ?? entry.discovered!.title;
    final type = entry.trackCount <= 1 ? 'Single' : 'Album';
    final year = entry.sortDate?.year;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
              child: coverPath != null
                  ? Image(
                      image: coverImageProvider(context,
                          path: coverPath!, width: 64, height: 64),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 64,
                      height: 64,
                      color: const Color(0xFF2A2A2A),
                      child: const Icon(Icons.album,
                          color: Colors.white54, size: 28),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    '$type${year != null ? ' • $year' : ''} • ${entry.trackCount} titre${entry.trackCount > 1 ? 's' : ''}',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          GlassIconButton(icon: Icons.play_arrow_rounded, onPressed: onPlay),
        ],
      ),
    );
  }
}

class _MissingReleaseTrackRow extends StatelessWidget {
  final ReleaseTrack track;
  final DownloadUiState? downloadState;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;

  const _MissingReleaseTrackRow({
    required this.track,
    required this.downloadState,
    required this.showDownloadButton,
    required this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(track.title,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(track.artistName,
                    style: const TextStyle(
                        color: Colors.white24, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (track.duration != null) ...[
            Text(formatDuration(track.duration!),
                style: const TextStyle(color: Colors.white24, fontSize: 12)),
            const SizedBox(width: 12),
          ],
          DownloadStateIcon(
            state: downloadState,
            showDownloadButton: showDownloadButton,
            onDownloadTap: onDownloadTap,
            size: 18,
          ),
        ],
      ),
    );
  }
}
