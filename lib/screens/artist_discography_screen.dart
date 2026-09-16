import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../services/artist_discography.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../widgets/bottom_bar_reserve.dart';
import '../widgets/cover_image.dart';
import '../widgets/download_button.dart';
import '../widgets/track_tile.dart';
import 'album_screen.dart';
import 'discovered_album_screen.dart';

/// Discographie complete d'un artiste (mobile) : tous ses albums/singles
/// (locaux + Deezer) avec leur tracklist entiere -- la page artiste elle
/// meme ne montre plus que 4 albums pour rester legere (retour utilisateur :
/// trop de contenu d'un coup rendait la page artiste lourde a charger).
class ArtistDiscographyScreen extends StatefulWidget {
  final String artistName;
  const ArtistDiscographyScreen({super.key, required this.artistName});

  @override
  State<ArtistDiscographyScreen> createState() =>
      _ArtistDiscographyScreenState();
}

class _ArtistDiscographyScreenState extends State<ArtistDiscographyScreen> {
  final _discovery = DiscoveryService();
  final _downloadWorker = DownloadWorkerService();
  final Map<int, DownloadUiState> _downloadStates = {};

  List<ArtistAlbumEntry> _entries = [];
  final Map<int, List<ReleaseTrack>> _tracksByEntry = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
      entry.local?.coverPath ??
      entry.discovered?.coverBigUrl ??
      entry.discovered?.coverUrl;

  void _openRelease(AppState state, ArtistAlbumEntry entry) {
    if (entry.local != null) {
      state.pushOverlay(
          AlbumScreen(album: entry.local!, filterArtist: widget.artistName));
    } else {
      state.pushOverlay(DiscoveredAlbumScreen(
          album: entry.discovered!, filterArtist: widget.artistName));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => state.popOverlay(),
        ),
        title: Text('Discographie · ${widget.artistName}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1DB954)))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (var i = 0; i < _entries.length; i++) ...[
                  _ReleaseHeader(
                    entry: _entries[i],
                    coverPath: _coverPath(_entries[i]),
                    onTap: () => _openRelease(state, _entries[i]),
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
                  if (_tracksByEntry[i] == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white38),
                        ),
                      ),
                    )
                  else
                    for (final rt in _tracksByEntry[i]!)
                      Selector<AppState, Track?>(
                        selector: (_, s) => s.currentTrack,
                        builder: (context, currentTrack, __) {
                          if (rt.local != null) {
                            return TrackTile(
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
                              onLike: () => state.toggleLike(rt.local!.id),
                            );
                          }
                          return _MissingReleaseTrackTile(
                            track: rt,
                            downloadState: rt.discovered != null
                                ? _downloadStates[rt.discovered!.id]
                                : null,
                            showDownloadButton: _downloadWorker.isConfigured,
                            onDownloadTap: () => _downloadTrack(rt),
                          );
                        },
                      ),
                  const SizedBox(height: 20),
                ],
                SizedBox(height: bottomBarReserve(context)),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: coverPath != null
                  ? Image(
                      image: coverImageProvider(context,
                          path: coverPath!, width: 56, height: 56),
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      color: const Color(0xFF2A2A2A),
                      child: const Icon(Icons.album,
                          color: Colors.white54, size: 26),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    '$type${year != null ? ' • $year' : ''} • ${entry.trackCount} titre${entry.trackCount > 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_fill,
                color: Color(0xFF1DB954), size: 32),
            onPressed: onPlay,
          ),
        ],
      ),
    );
  }
}

class _MissingReleaseTrackTile extends StatelessWidget {
  final ReleaseTrack track;
  final DownloadUiState? downloadState;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;

  const _MissingReleaseTrackTile({
    required this.track,
    required this.downloadState,
    required this.showDownloadButton,
    required this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: const SizedBox(width: 24),
      title: Text(track.title,
          style: const TextStyle(color: Colors.white38, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(track.artistName,
          style: const TextStyle(color: Colors.white24, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      trailing: DownloadStateIcon(
        state: downloadState,
        showDownloadButton: showDownloadButton,
        onDownloadTap: onDownloadTap,
        size: 20,
      ),
    );
  }
}
