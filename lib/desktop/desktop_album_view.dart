import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/album.dart';
import '../models/discovered_album.dart';
import '../models/discovered_track.dart';
import '../models/recent_play.dart';
import '../models/track.dart';
import '../providers/app_state.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../services/matching_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/download_button.dart';
import '../widgets/smooth_scroll.dart';
import 'desktop_track_row.dart';
import 'glass.dart';

/// Page album local desktop : equivalent de AlbumScreen (mobile). Affiche
/// tout le tracklist Deezer de reference quand il est trouve -- les titres
/// deja sur le NAS restent lisibles (DesktopTrackRow), les autres sont
/// grises avec un bouton de telechargement, exactement comme
/// DesktopDiscoveredAlbumView pour un album pas encore possede.
///
/// Avant ce fichier, ouvrir un album local passait par DesktopCollectionView
/// (vue generique reutilisee aussi par les playlists/titres likes), qui
/// n'a jamais eu connaissance de Deezer : un album partiellement possede
/// n'affichait donc que les titres deja telecharges, sans indiquer lesquels
/// manquaient.
class DesktopAlbumView extends StatefulWidget {
  final Album album;
  final String? filterArtist;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenArtist;

  const DesktopAlbumView({
    super.key,
    required this.album,
    this.filterArtist,
    required this.onBack,
    required this.onOpenArtist,
  });

  @override
  State<DesktopAlbumView> createState() => _DesktopAlbumViewState();
}

class _DesktopAlbumViewState extends State<DesktopAlbumView> {
  final _discovery = DiscoveryService();
  final _downloadWorker = DownloadWorkerService();
  final _scrollController = SmoothScrollController();
  List<DiscoveredTrack> _discoveredTracks = [];
  // Reste a false le temps du tout premier chargement pour ne montrer ni
  // les titres locaux seuls ni une liste incomplete avant d'avoir la
  // reponse Deezer complete (evite le "flash" 4 titres -> 16 titres). Les
  // rechargements suivants (fin de synchro) ne remettent pas ce flag a
  // false : le contenu deja affiche reste visible pendant la mise a jour
  // silencieuse.
  bool _hasLoadedOnce = false;
  final Map<int, DownloadUiState> _downloadStates = {};

  AppState? _appState;
  bool _wasSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadDeezerTracks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.read<AppState>();
    if (!identical(appState, _appState)) {
      _appState?.removeListener(_onAppStateChanged);
      _appState = appState;
      _wasSyncing = appState.isSyncing;
      appState.addListener(_onAppStateChanged);
    }
  }

  /// Recharge le tracklist Deezer une fois la synchro NAS terminee : si cet
  /// ecran a ete ouvert pendant une synchro en cours, le statut "possede"
  /// calcule sur une bibliotheque encore incomplete serait fige et faux
  /// pour le reste de la session (voir aussi DesktopArtistView).
  void _onAppStateChanged() {
    final syncing = _appState?.isSyncing ?? false;
    if (_wasSyncing && !syncing && mounted) {
      _loadDeezerTracks();
    }
    _wasSyncing = syncing;
  }

  @override
  void dispose() {
    _appState?.removeListener(_onAppStateChanged);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDeezerTracks() async {
    try {
      final albums =
          await _discovery.searchAlbums(widget.album.title, limit: 10);
      DiscoveredAlbum? match;
      for (final a in albums) {
        if (MatchingService.albumsMatch(a.title, widget.album.title)) {
          match = a;
          break;
        }
      }
      if (match != null) {
        final tracks = await _discovery.getAlbumTracks(match.id);
        if (mounted) setState(() => _discoveredTracks = tracks);
      }
    } catch (_) {}
    if (mounted) setState(() => _hasLoadedOnce = true);
  }

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
      if (mounted) await _loadDeezerTracks();
      if (mounted) setState(() => _downloadStates.remove(track.id));
    } else {
      setState(() => _downloadStates[track.id] = DownloadUiState.failed);
    }
  }

  /// Fusionne les pistes locales par titre (garde la version likee) : evite
  /// qu'un titre apparaisse deux fois si le NAS a un doublon range dans cet
  /// album.
  List<Track> _dedupByTitle(List<Track> tracks) {
    final byTitle = <String, Track>{};
    for (final t in tracks) {
      final key = MatchingService.normalize(t.title);
      final existing = byTitle[key];
      if (existing == null || (!existing.isLiked && t.isLiked)) {
        byTitle[key] = t;
      }
    }
    return byTitle.values.toList();
  }

  /// Construit la liste affichee a partir du tracklist Deezer (ordre et
  /// contenu de reference) : pour chaque titre, on cherche s'il existe en
  /// local (lisible) ou non (grise+telechargeable). Les pistes locales
  /// possedees mais absentes du tracklist Deezer (bonus...) sont ajoutees a
  /// la suite.
  List<_AlbumListItem> _buildTrackList(List<Track> localTracks) {
    if (_discoveredTracks.isEmpty) {
      return [for (final t in localTracks) _AlbumListItem(localTrack: t)];
    }

    final byTitle = {
      for (final t in localTracks) MatchingService.normalize(t.title): t
    };
    final items = <_AlbumListItem>[];
    final usedKeys = <String>{};

    for (final dt in _discoveredTracks) {
      final dtTitle = MatchingService.normalize(dt.title);
      final exact = byTitle[dtTitle];
      final match = exact ??
          localTracks.cast<Track?>().firstWhere(
                (t) => MatchingService.titlesMatch(t!.title, dt.title),
                orElse: () => null,
              );

      if (match != null) {
        usedKeys.add(MatchingService.normalize(match.title));
        items.add(_AlbumListItem(localTrack: match));
      } else {
        items.add(_AlbumListItem(discoveredTrack: dt));
      }
    }

    for (final t in localTracks) {
      if (!usedKeys.contains(MatchingService.normalize(t.title))) {
        items.add(_AlbumListItem(localTrack: t));
      }
    }
    return items;
  }

  void _recordRecent(AppState state) {
    state.recordRecentPlay(RecentPlay(
      type: RecentPlayType.album,
      id: widget.album.id,
      title: widget.album.title,
      subtitle: widget.album.artist,
      coverPath: widget.album.coverPath,
      playedAt: DateTime.now(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    var albumTracks = state.allTracks
        .where((t) => MatchingService.albumsMatch(t.album, widget.album.title))
        .toList();

    if (widget.filterArtist != null) {
      bool artistMatch(String? field) =>
          MatchingService.artistFieldContains(field, widget.filterArtist!);
      albumTracks = albumTracks
          .where((t) => artistMatch(t.artist) || artistMatch(t.albumArtist))
          .toList();
    }

    albumTracks = _dedupByTitle(albumTracks)
      ..sort((a, b) => a.title.compareTo(b.title));
    final items = _buildTrackList(albumTracks);
    final isLiked = widget.album.isSaved;

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
                    album: widget.album,
                    trackCount: _hasLoadedOnce ? items.length : albumTracks.length,
                    isLiked: isLiked,
                    onToggleLike: () =>
                        state.toggleLikeAlbum(widget.album.id),
                    onOpenArtist: () =>
                        widget.onOpenArtist(widget.album.artist),
                    onPlay: albumTracks.isEmpty
                        ? null
                        : () {
                            _recordRecent(state);
                            state.playTrack(albumTracks.first,
                                trackList: albumTracks);
                          },
                    onShuffle: albumTracks.isEmpty
                        ? null
                        : () {
                            _recordRecent(state);
                            final shuffled = List<Track>.of(albumTracks)
                              ..shuffle();
                            state.playTrack(shuffled.first,
                                trackList: shuffled);
                          },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                if (!_hasLoadedOnce)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => const _SkeletonTrackRow(),
                        childCount: albumTracks.length.clamp(1, 8),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = items[index];
                        if (item.localTrack != null) {
                          final track = item.localTrack!;
                          return Selector<AppState, Track?>(
                            selector: (_, s) => s.currentTrack,
                            builder: (context, currentTrack, __) =>
                                DesktopTrackRow(
                              track: track,
                              isPlaying: currentTrack?.id == track.id,
                              onTap: () {
                                _recordRecent(state);
                                state.playTrack(track,
                                    trackList: albumTracks);
                              },
                              onLike: () => state.toggleLike(track.id),
                              onMore: () {},
                              onOpenArtist: widget.onOpenArtist,
                            ),
                          );
                        }
                        final dt = item.discoveredTrack!;
                        return _DiscoveredTrackRow(
                          index: index,
                          track: dt,
                          downloadState: _downloadStates[dt.id],
                          showDownloadButton: _downloadWorker.isConfigured,
                          onDownloadTap: () => _downloadTrack(dt),
                        );
                      },
                      childCount: items.length,
                    ),
                  ),
                const SliverToBoxAdapter(
                    child: SizedBox(height: DesktopGlass.playerBarReserve)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumListItem {
  final Track? localTrack;
  final DiscoveredTrack? discoveredTrack;
  const _AlbumListItem({this.localTrack, this.discoveredTrack});
}

/// Ligne fantome affichee pendant le tout premier chargement Deezer, le
/// temps d'avoir la tracklist complete a montrer d'un coup.
class _SkeletonTrackRow extends StatelessWidget {
  const _SkeletonTrackRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  height: 13,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 120,
                  height: 11,
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

class _Header extends StatelessWidget {
  final Album album;
  final int trackCount;
  final bool isLiked;
  final VoidCallback onToggleLike;
  final VoidCallback onOpenArtist;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  const _Header({
    required this.album,
    required this.trackCount,
    required this.isLiked,
    required this.onToggleLike,
    required this.onOpenArtist,
    required this.onPlay,
    required this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    final coverPath = album.coverPath;
    final exists = context.read<AppState>().coverExists(coverPath);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesktopGlass.radiusMd),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 12)),
            ],
            image: exists && coverPath != null
                ? DecorationImage(
                    image: coverImageProvider(context,
                        path: coverPath, width: 200, height: 200),
                    fit: BoxFit.cover,
                    onError: (_, __) {})
                : null,
            color: const Color(0xFF2A2A2A),
          ),
          child: !exists || coverPath == null
              ? const Icon(Icons.album, color: Colors.white54, size: 64)
              : null,
        ),
        const SizedBox(width: 28),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                album.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              DesktopHoverable(
                onTap: onOpenArtist,
                borderRadius: BorderRadius.circular(20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: const Color(0xFF3E3E3E),
                      backgroundImage: exists && coverPath != null
                          ? coverImageProvider(context,
                              path: coverPath, width: 26, height: 26)
                          : null,
                      onBackgroundImageError:
                          exists && coverPath != null ? (_, __) {} : null,
                      child: !exists || coverPath == null
                          ? const Icon(Icons.person,
                              color: Colors.white54, size: 13)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      album.artist,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text('Album • $trackCount titre${trackCount > 1 ? 's' : ''}',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12)),
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
                        padding:
                            EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                  const SizedBox(width: 12),
                  GlassIconButton(
                    icon: isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? DesktopGlass.accent : Colors.white54,
                    onPressed: onToggleLike,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiscoveredTrackRow extends StatelessWidget {
  final int index;
  final DiscoveredTrack track;
  final DownloadUiState? downloadState;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;

  const _DiscoveredTrackRow({
    required this.index,
    required this.track,
    required this.downloadState,
    required this.showDownloadButton,
    required this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text('${index + 1}',
                style: const TextStyle(color: Colors.white38, fontSize: 14),
                textAlign: TextAlign.center),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.title,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  track.artistName,
                  style: const TextStyle(color: Colors.white24, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          DownloadStateIcon(
            state: downloadState,
            showDownloadButton: showDownloadButton,
            onDownloadTap: onDownloadTap,
            size: 16,
          ),
        ],
      ),
    );
  }
}
