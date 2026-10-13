import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/download_button.dart';
import '../features/discovered_album/discovered_album_model.dart';
import '../features/shared/download_waiters.dart';
import '../services/download_worker_service.dart' show DownloadUiState;
import '../providers/app_state.dart';
import '../models/discovered_album.dart';
import '../models/discovered_track.dart';
import '../models/track.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/cover_image.dart';
import '../widgets/player/player_options_sheet.dart';
import 'artist_screen.dart';
import '../widgets/bottom_bar_reserve.dart';

class DiscoveredAlbumScreen extends StatefulWidget {
  final DiscoveredAlbum? album;
  final int? albumId;
  final String? filterArtist; // ← NOUVEAU : filtre les tracks par artiste

  const DiscoveredAlbumScreen({
    super.key,
    this.album,
    this.albumId,
    this.filterArtist,
  }) : assert(album != null || albumId != null);

  factory DiscoveredAlbumScreen.fromAlbumId(int id, {String? filterArtist}) {
    return DiscoveredAlbumScreen(albumId: id, filterArtist: filterArtist);
  }

  @override
  State<DiscoveredAlbumScreen> createState() => _DiscoveredAlbumScreenState();
}

class _DiscoveredAlbumScreenState extends State<DiscoveredAlbumScreen> {
  late final DiscoveredAlbumModel _model;

  @override
  void initState() {
    super.initState();
    _model = DiscoveredAlbumModel(
      album: widget.album,
      albumId: widget.albumId,
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

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final album = _model.album;

    if (_model.isLoading || album == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF1DB954)),
        ),
      );
    }

    // filterArtist n'est plus applique ici : une fois l'album ouvert, on
    // montre TOUS ses titres plutot que de risquer de tout masquer parce que
    // l'artiste par lequel on est arrive n'apparait qu'en featuring sur
    // chaque titre Deezer (retour utilisateur).
    final displayTracks = _model.tracks;
    final resolvedArtistName = _model.artistName;
    final localMatches = _model.localMatches();
    final missingTracks =
        displayTracks.where((dt) => localMatches[dt.id] == null).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => state.popOverlay(),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                        image: album.coverBigUrl != null
                            ? DecorationImage(
                                image: coverImageProvider(context,
                                    path: album.coverBigUrl!,
                                    width: 200,
                                    height: 200),
                                fit: BoxFit.cover,
                                onError: (_, __) {},
                              )
                            : null,
                        color: const Color(0xFF2A2A2A),
                      ),
                      child: album.coverBigUrl == null
                          ? const Icon(Icons.album,
                              color: Colors.white54, size: 64)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    album.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      state.pushOverlay(
                        ArtistScreen(artistName: resolvedArtistName),
                      );
                    },
                    child: Row(
                      children: [
                        // Vraie photo d'artiste (pas la cover de CET album) --
                        // meme widget que AlbumScreen/l'etagere "Artistes du
                        // moment", meme fix que DesktopDiscoveredAlbumView
                        // (retour utilisateur).
                        ArtistAvatar(
                          artistName: resolvedArtistName,
                          fallbackCoverPath: album.coverUrl,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          resolvedArtistName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Album • ${displayTracks.length} titres',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (missingTracks.isNotEmpty && _model.canDownload) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => _model.downloadMissing(missingTracks,
                          wait: waitSilently),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                          'Télécharger (${missingTracks.length} titre${missingTracks.length > 1 ? 's' : ''})'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = displayTracks[index];
                  final localTrack = localMatches[track.id];
                  return _DiscoveredTrackTile(
                    index: index,
                    track: track,
                    localTrack: localTrack,
                    downloadState: _model.downloadStateOf(track.id),
                    showDownloadButton: _model.canDownload,
                    onTap: () {
                      if (localTrack != null) _model.play(localTrack);
                    },
                    onDownloadTap: () => _model.downloadTrack(track,
                        wait: waitWithProgressDialog(context)),
                  );
                },
                childCount: displayTracks.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
              child: SizedBox(height: bottomBarReserve(context))),
        ],
      ),
    );
  }
}

class _DiscoveredTrackTile extends StatelessWidget {
  final int index;
  final DiscoveredTrack track;
  // Titre local resolu (voir _findLocalTrack) : non-null exactement quand
  // le titre est reellement lisible/likable/"..."-able. Remplace
  // track.isInLibrary (un matching separe, plus permissif -- pouvait dire
  // "disponible" pour un titre qu'aucune tracklist locale ne retrouvait
  // vraiment, ex: "Instant Crush (Drumless Edition)" affiche en blanc/
  // cliquable sans qu'aucune version drumless soit sur le NAS) comme signal
  // pour tout le style/l'etat de cette ligne, meme logique que
  // DesktopDiscoveredAlbumView._DiscoveredTrackRow.
  final Track? localTrack;
  final VoidCallback onTap;
  final DownloadUiState? downloadState;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;

  const _DiscoveredTrackTile({
    required this.index,
    required this.track,
    required this.localTrack,
    required this.onTap,
    required this.downloadState,
    required this.showDownloadButton,
    required this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAvailable = localTrack != null;
    return InkWell(
      onTap: isAvailable ? onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: isAvailable ? Colors.white54 : Colors.white38,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
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
                    // Le vrai tag local quand on l'a (fiable), pas le champ
                    // Deezer (peut etre "Inconnu" pour ce titre precis meme
                    // quand le titre est bien identifie/lisible).
                    localTrack?.artist ?? track.artistName,
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
            if (isAvailable) ...[
              IconButton(
                icon: Icon(
                  localTrack!.isLiked ? Icons.favorite : Icons.favorite_border,
                  color: localTrack!.isLiked
                      ? const Color(0xFF1DB954)
                      : Colors.white54,
                  size: 18,
                ),
                onPressed: () =>
                    context.read<AppState>().toggleLike(localTrack!.id),
                splashRadius: 18,
              ),
              IconButton(
                icon: const Icon(Icons.more_vert,
                    color: Colors.white54, size: 18),
                onPressed: () => showPlayerOptions(context, localTrack!),
                splashRadius: 18,
              ),
            ] else
              DownloadStateIcon(
                state: downloadState,
                showDownloadButton: showDownloadButton,
                onDownloadTap: onDownloadTap,
              ),
          ],
        ),
      ),
    );
  }
}
