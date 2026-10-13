import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../features/artist_discography/artist_discography_model.dart';
import '../features/shared/download_waiters.dart';
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
  late final ArtistDiscographyModel _model;

  @override
  void initState() {
    super.initState();
    _model = ArtistDiscographyModel(
      artistName: widget.artistName,
      discovery: context.read<DiscoveryService>(),
      library: context.read<AppState>(),
    )..addListener(_onModelChanged);
  }

  void _onModelChanged() => setState(() {});

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

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
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
      ),
      body: _model.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1DB954)))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (var i = 0; i < _model.entries.length; i++) ...[
                  _ReleaseHeader(
                    entry: _model.entries[i],
                    coverPath: releaseCoverPath(_model.entries[i]),
                    onTap: () => _openRelease(state, _model.entries[i]),
                    onPlay: () {
                      final tracks = _model
                              .tracksOf(i)
                              ?.where((t) => t.local != null)
                              .map((t) => t.local!)
                              .toList() ??
                          const <Track>[];
                      if (tracks.isNotEmpty) {
                        state.playTrack(tracks.first, trackList: tracks);
                      }
                    },
                  ),
                  if (_model.tracksOf(i) == null)
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
                    for (final rt in _model.tracksOf(i)!)
                      Selector<AppState, Track?>(
                        selector: (_, s) => s.displayTrack,
                        builder: (context, currentTrack, __) {
                          if (rt.local != null) {
                            return TrackTile(
                              track: rt.local!,
                              isPlaying: currentTrack?.id == rt.local!.id,
                              onTap: () {
                                final localTracks = _model
                                    .tracksOf(i)!
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
                                ? _model.downloadStateOf(rt.discovered!.id)
                                : null,
                            showDownloadButton: _model.canDownload,
                            onDownloadTap: () =>
                                _model.downloadRelease(rt, wait: waitSilently),
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
