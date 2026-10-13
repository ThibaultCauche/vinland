import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../features/artist_discography/artist_discography_model.dart';
import '../features/shared/download_waiters.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/discovered_album.dart';
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
  late final ArtistDiscographyModel _model;
  final _scrollController = SmoothScrollController();

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
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();

    return Padding(
      padding: const EdgeInsets.only(top: DesktopGlass.topInsetCompact),
      child: _model.isLoading
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
                        if (_model.discoveredArtist?.pictureBigUrl != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image(
                              image: coverImageProvider(context,
                                  path: _model.discoveredArtist!.pictureBigUrl!,
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
                for (var i = 0; i < _model.entries.length; i++) ...[
                  SliverToBoxAdapter(
                    child: _ReleaseHeader(
                      entry: _model.entries[i],
                      coverPath: releaseCoverPath(_model.entries[i]),
                      onTap: () {
                        final entry = _model.entries[i];
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
                  ),
                  if (_model.tracksOf(i) == null)
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
                          final rt = _model.tracksOf(i)![trackIndex];
                          return Selector<AppState, Track?>(
                            selector: (_, s) => s.displayTrack,
                            builder: (context, currentTrack, __) {
                              if (rt.local != null) {
                                return DesktopTrackRow(
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
                                  onMore: () {},
                                );
                              }
                              return _MissingReleaseTrackRow(
                                track: rt,
                                downloadState: rt.discovered != null
                                    ? _model.downloadStateOf(rt.discovered!.id)
                                    : null,
                                showDownloadButton: _model.canDownload,
                                onDownloadTap: () => _model.downloadRelease(rt,
                                    wait: waitWithProgressDialog(context)),
                              );
                            },
                          );
                        },
                        childCount: _model.tracksOf(i)!.length,
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
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                    style: const TextStyle(color: Colors.white24, fontSize: 12),
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
