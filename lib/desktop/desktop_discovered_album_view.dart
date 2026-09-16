import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/discovered_album.dart';
import '../models/discovered_track.dart';
import '../models/track.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../services/local_track_matcher.dart';
import '../widgets/smooth_scroll.dart';
import '../widgets/cover_image.dart';
import 'desktop_hero_card.dart'
    show
        DesktopHeroMenuAction,
        DesktopMoreMenuButton,
        pickPlaylistAndAddTracks,
        trackMoreMenuActions;
import '../widgets/artist_avatar.dart';
import 'glass.dart';

enum _DownloadUiState { downloading, failed }

/// Page album "decouvert" desktop : equivalent de DiscoveredAlbumScreen
/// (mobile) pour un album Deezer qui n'a pas de correspondance locale
/// complete -- tracklist grisee, seuls les titres presents sur le NAS sont
/// lisibles.
class DesktopDiscoveredAlbumView extends StatefulWidget {
  final DiscoveredAlbum? album;
  final int? albumId;
  final String? filterArtist;
  final ValueChanged<String> onOpenArtist;

  const DesktopDiscoveredAlbumView({
    super.key,
    this.album,
    this.albumId,
    this.filterArtist,
    required this.onOpenArtist,
  }) : assert(album != null || albumId != null);

  @override
  State<DesktopDiscoveredAlbumView> createState() =>
      _DesktopDiscoveredAlbumViewState();
}

class _DesktopDiscoveredAlbumViewState
    extends State<DesktopDiscoveredAlbumView> {
  final _discovery = DiscoveryService();
  final _downloadWorker = DownloadWorkerService();
  DiscoveredAlbum? _album;
  List<DiscoveredTrack> _tracks = [];
  bool _isLoading = true;
  final _scrollController = SmoothScrollController();
  final Map<int, _DownloadUiState> _downloadStates = {};

  AppState? _appState;
  bool _wasSyncing = false;

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

  /// Voir discovered_album_screen.dart : recharge automatiquement des
  /// qu'une synchro Navidrome se termine pendant que cet ecran est ouvert.
  void _onAppStateChanged() {
    final syncing = _appState?.isSyncing ?? false;
    if (_wasSyncing && !syncing && mounted) {
      _load();
    }
    _wasSyncing = syncing;
  }

  Future<void> _downloadTrack(DiscoveredTrack track) async {
    setState(() => _downloadStates[track.id] = _DownloadUiState.downloading);

    final jobId = await _downloadWorker.requestDownload(
      artist: track.artistName,
      title: track.title,
      album: track.albumName == 'Inconnu' ? null : track.albumName,
    );
    if (jobId == null) {
      if (mounted) {
        setState(() => _downloadStates[track.id] = _DownloadUiState.failed);
      }
      return;
    }

    final status = await _downloadWorker.waitForCompletion(jobId);
    if (!mounted) return;

    if (status.state == DownloadJobState.done) {
      // Voir discovered_album_screen.dart : syncRecentlyAdded() est un
      // aller-retour rapide (juste les derniers albums), contrairement a
      // syncNavidrome() qui reconstruit toute la bibliotheque lot par lot et
      // la rend temporairement injouable le temps d'une synchro complete.
      await context.read<AppState>().syncRecentlyAdded();
      if (mounted) await _load();
      if (mounted) setState(() => _downloadStates.remove(track.id));
    } else {
      setState(() => _downloadStates[track.id] = _DownloadUiState.failed);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _appState?.removeListener(_onAppStateChanged);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.album != null) {
      _album = widget.album;
    } else if (widget.albumId != null) {
      _album = await _discovery.getAlbum(widget.albumId!);
    }
    if (_album != null) {
      _tracks = await _discovery.getAlbumTracks(_album!.id);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  bool _artistContains(String? artistField, String search) {
    if (artistField == null) return false;
    final s = search.toLowerCase();
    final f = artistField.toLowerCase();
    if (f == s) return true;
    if (f.contains(s)) return true;
    return f.split(RegExp(r'[/&,]')).any((p) => p.trim() == s);
  }

  Track? _findLocalTrack(DiscoveredTrack dt) =>
      findLocalTrackMatch(dt, context.read<AppState>().allTracks);

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final album = _album;

    // topInsetCompact -- meme raison que DesktopCollectionView.
    return Padding(
      padding: const EdgeInsets.only(top: DesktopGlass.topInsetCompact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: (_isLoading || album == null)
                ? const Center(
                    child:
                        CircularProgressIndicator(color: DesktopGlass.accent))
                : _buildContent(context, state, album),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, AppState state, DiscoveredAlbum album) {
    final displayTracks = widget.filterArtist != null
        ? _tracks
            .where((t) => _artistContains(t.artistName, widget.filterArtist!))
            .toList()
        : _tracks;

    // Titres deja sur le NAS (jouables/telechargeables/ajoutables a une
    // playlist) vs. encore a telecharger -- cette vue s'ouvre justement
    // parce que l'album n'est PAS entierement local, contrairement a
    // DesktopAlbumView qui a toujours au moins un titre jouable. Sans ce
    // menu, un album comme celui-ci n'avait AUCUNE option (retour
    // utilisateur : "pourquoi certains albums n'ont pas d'option").
    final localTracks =
        displayTracks.map(_findLocalTrack).whereType<Track>().toList();
    final missingTracks = [
      for (final dt in displayTracks)
        if (_findLocalTrack(dt) == null) dt,
    ];
    final moreActions = [
      if (localTracks.isNotEmpty)
        DesktopHeroMenuAction(
          label: "Ajouter à la file d'attente",
          icon: Icons.playlist_add,
          onTap: () {
            for (final t in localTracks) {
              state.addToQueue(t);
            }
          },
        ),
      if (missingTracks.isNotEmpty)
        DesktopHeroMenuAction(
          label: 'Télécharger',
          icon: Icons.download_outlined,
          onTap: () {
            for (final dt in missingTracks) {
              _downloadTrack(dt);
            }
          },
        ),
      if (localTracks.isNotEmpty)
        DesktopHeroMenuAction(
          label: 'Ajouter à une playlist',
          icon: Icons.playlist_add_check,
          onTap: () => pickPlaylistAndAddTracks(context, state, localTracks),
        ),
    ];

    // album.artistName vient du champ "artist" de l'ALBUM cote Deezer, qui
    // est "Inconnu" pour certaines sorties (compilations, singles mal
    // catalogues...) meme quand les TITRES individuels ont, eux, un artiste
    // correctement renseigne -- repli sur le premier titre qui en a un
    // plutot que d'afficher "Inconnu" alors que l'info existe ailleurs
    // (retour utilisateur).
    final resolvedArtistName = album.artistName != 'Inconnu'
        ? album.artistName
        : _tracks
            .map((t) => t.artistName)
            .firstWhere((a) => a != 'Inconnu', orElse: () => album.artistName);

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Row(
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
                  image: album.coverBigUrl != null
                      ? DecorationImage(
                          image: coverImageProvider(context,
                              path: album.coverBigUrl!,
                              width: 200,
                              height: 200),
                          fit: BoxFit.cover,
                          onError: (_, __) {})
                      : null,
                  color: const Color(0xFF2A2A2A),
                ),
                child: album.coverBigUrl == null
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
                      onTap: () => widget.onOpenArtist(resolvedArtistName),
                      borderRadius: BorderRadius.circular(20),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Vraie photo d'artiste (pas la cover de cet
                          // album) -- meme widget que l'etagere "Artistes
                          // du moment" de l'accueil et DesktopAlbumView.
                          ArtistAvatar(
                            artistName: resolvedArtistName,
                            fallbackCoverPath: album.coverUrl,
                            size: 26,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            resolvedArtistName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('Album • ${displayTracks.length} titres',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                        const SizedBox(width: 10),
                        const Icon(Icons.cloud_off,
                            color: Colors.white24, size: 12),
                        const SizedBox(width: 4),
                        const Text('Non disponible en integralite sur le NAS',
                            style:
                                TextStyle(color: Colors.white24, fontSize: 11)),
                      ],
                    ),
                    if (moreActions.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DesktopMoreMenuButton(actions: moreActions),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _DiscoveredTrackRow(
              index: index,
              track: displayTracks[index],
              localTrack: _findLocalTrack(displayTracks[index]),
              downloadState: _downloadStates[displayTracks[index].id],
              showDownloadButton: _downloadWorker.isConfigured,
              onTap: () {
                final localTrack = _findLocalTrack(displayTracks[index]);
                if (localTrack != null) state.playTrack(localTrack);
              },
              onDownloadTap: () => _downloadTrack(displayTracks[index]),
            ),
            childCount: displayTracks.length,
          ),
        ),
        const SliverToBoxAdapter(
            child: SizedBox(height: DesktopGlass.playerBarReserve)),
      ],
    );
  }
}

class _DiscoveredTrackRow extends StatelessWidget {
  final int index;
  final DiscoveredTrack track;
  // Titre local resolu (voir _findLocalTrack) : non-null exactement quand
  // track.isInLibrary est vrai, requis pour le like/menu "..." (retour
  // utilisateur : une simple coche ne menait a aucune action).
  final Track? localTrack;
  final VoidCallback onTap;
  final _DownloadUiState? downloadState;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;

  const _DiscoveredTrackRow({
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
    // localTrack != null (pas track.isInLibrary) pour TOUT le style/l'etat
    // de cette ligne -- track.isInLibrary vient d'un matching separe
    // (DiscoveryService._markTrackLibraryStatus, plus permissif) qui pouvait
    // dire "disponible" (texte blanc, ligne cliquable) pour un titre que
    // localTrack (le matching reellement utilise pour lire/liker/menu,
    // titre exact) ne retrouvait pas -- ex: "Instant Crush (Drumless
    // Edition)" affiche en blanc/cliquable alors qu'aucune version drumless
    // n'est sur le NAS (retour utilisateur). Un seul signal, le plus
    // strict, pour que l'affichage corresponde toujours a ce qui est
    // reellement jouable.
    final isAvailable = localTrack != null;
    return InkWell(
      onTap: isAvailable ? onTap : null,
      borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text('${index + 1}',
                  style: TextStyle(
                      color: isAvailable ? Colors.white54 : Colors.white38,
                      fontSize: 14),
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
                    style: TextStyle(
                      color: isAvailable ? Colors.white : Colors.white38,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
            if (localTrack != null) ...[
              // Like puis "..." -- une simple coche ne menait a aucune
              // action, remplacee par les memes options que partout ailleurs
              // (retour utilisateur).
              GlassIconButton(
                icon: localTrack!.isLiked
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: localTrack!.isLiked
                    ? DesktopGlass.accent
                    : Colors.white54,
                size: 16,
                onPressed: () =>
                    context.read<AppState>().toggleLike(localTrack!.id),
              ),
              const SizedBox(width: 4),
              DesktopMoreMenuButton(
                actions: trackMoreMenuActions(
                    context, context.read<AppState>(), localTrack!),
              ),
            ] else if (downloadState == _DownloadUiState.downloading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white38,
                ),
              )
            else if (showDownloadButton)
              InkWell(
                onTap: onDownloadTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    downloadState == _DownloadUiState.failed
                        ? Icons.error_outline
                        : Icons.download_rounded,
                    color: downloadState == _DownloadUiState.failed
                        ? Colors.redAccent
                        : Colors.white54,
                    size: 18,
                  ),
                ),
              )
            else
              const Icon(Icons.cloud_off, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }
}
