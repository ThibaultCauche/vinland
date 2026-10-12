import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../features/album/album_model.dart';
import '../features/shared/download_waiters.dart';
import '../models/album.dart';
import '../models/discovered_track.dart';
import '../models/pinned_item.dart';
import '../models/track.dart';
import '../providers/app_state.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../services/deep_link_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/download_button.dart';
import '../widgets/smooth_scroll.dart';
import 'desktop_hero_card.dart'
    show DesktopHeroMenuAction, DesktopMoreMenuButton, pickPlaylistAndAddTracks;
import '../widgets/artist_avatar.dart';
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
  final ValueChanged<String> onOpenArtist;

  const DesktopAlbumView({
    super.key,
    required this.album,
    this.filterArtist,
    required this.onOpenArtist,
  });

  @override
  State<DesktopAlbumView> createState() => _DesktopAlbumViewState();
}

class _DesktopAlbumViewState extends State<DesktopAlbumView> {
  late final AlbumModel _model;
  final _scrollController = SmoothScrollController();

  @override
  void initState() {
    super.initState();
    _model = AlbumModel(
      album: widget.album,
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
    final state = context.watch<AppState>();

    final albumTracks = _model.localTracks;
    final items = _model.items(albumTracks);
    final isLiked = widget.album.isSaved;

    return Padding(
      padding: const EdgeInsets.only(top: DesktopGlass.topInsetCompact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    album: widget.album,
                    trackCount: _model.hasLoadedOnce
                        ? items.length
                        : albumTracks.length,
                    isLiked: isLiked,
                    onToggleLike: () => state.toggleLikeAlbum(widget.album.id),
                    onOpenArtist: () =>
                        widget.onOpenArtist(widget.album.artist),
                    onPlay: albumTracks.isEmpty
                        ? null
                        : () => _model.playAll(albumTracks),
                    onShuffle: albumTracks.isEmpty
                        ? null
                        : () => _model.playAll(albumTracks, shuffle: true),
                    moreActions: [
                      DesktopHeroMenuAction(
                        label: state.isPinned(
                                PinnedItemType.album, widget.album.id)
                            ? "Désépingler de l'accueil"
                            : "Épingler à l'accueil",
                        icon: state.isPinned(
                                PinnedItemType.album, widget.album.id)
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        onTap: () => state.togglePin(PinnedItem(
                          type: PinnedItemType.album,
                          id: widget.album.id,
                          title: widget.album.title,
                          subtitle: widget.album.artist,
                        )),
                      ),
                      if (albumTracks.isNotEmpty) ...[
                        DesktopHeroMenuAction(
                          label: "Ajouter à la file d'attente",
                          icon: Icons.playlist_add,
                          onTap: () {
                            for (final t in albumTracks) {
                              state.addToQueue(t);
                            }
                          },
                        ),
                        DesktopHeroMenuAction(
                          label: 'Télécharger',
                          icon: Icons.download_outlined,
                          onTap: () => state.downloadTracksOffline(albumTracks),
                        ),
                        DesktopHeroMenuAction(
                          label: 'Ajouter à une playlist',
                          icon: Icons.playlist_add_check,
                          onTap: () => pickPlaylistAndAddTracks(
                              context, state, albumTracks),
                        ),
                      ],
                    ],
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                if (!_model.hasLoadedOnce)
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
                        if (item.local != null) {
                          final track = item.local!;
                          return Selector<AppState, Track?>(
                            selector: (_, s) => s.displayTrack,
                            builder: (context, currentTrack, __) =>
                                DesktopTrackRow(
                              track: track,
                              isPlaying: currentTrack?.id == track.id,
                              onTap: () => _model.play(track, albumTracks),
                              onLike: () => state.toggleLike(track.id),
                              onMore: () {},
                              onOpenArtist: widget.onOpenArtist,
                            ),
                          );
                        }
                        final dt = item.discovered!;
                        return _DiscoveredTrackRow(
                          index: index,
                          track: dt,
                          downloadState: _model.downloadStateOf(dt.id),
                          showDownloadButton: _model.canDownload,
                          onDownloadTap: () => _model.downloadTrack(dt,
                              wait: waitWithProgressDialog(context)),
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
  final List<DesktopHeroMenuAction> moreActions;

  const _Header({
    required this.album,
    required this.trackCount,
    required this.isLiked,
    required this.onToggleLike,
    required this.onOpenArtist,
    required this.onPlay,
    required this.onShuffle,
    this.moreActions = const [],
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
                    // Vraie photo d'artiste (pas la cover de CET album) --
                    // meme widget que l'etagere "Artistes du moment" de
                    // l'accueil (retour utilisateur : ce badge montrait la
                    // cover de l'album au lieu du compositeur/artiste).
                    ArtistAvatar(
                      artistName: album.artist,
                      fallbackCoverPath: coverPath,
                      size: 26,
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
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
                  const SizedBox(width: 12),
                  GlassIconButton(
                    icon: Icons.ios_share,
                    onPressed: () => shareAlbum(album),
                  ),
                  if (context.read<AppState>().shareInboxConfigured) ...[
                    const SizedBox(width: 12),
                    GlassIconButton(
                      icon: Icons.send_outlined,
                      onPressed: () => showSendToFriendDialog(context,
                          type: 'album',
                          itemId: album.id,
                          title: album.title,
                          subtitle: album.artist),
                    ),
                  ],
                  if (moreActions.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    DesktopMoreMenuButton(actions: moreActions),
                  ],
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
