import 'dart:io';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/track.dart';
import '../models/discovered_track.dart';
import '../models/discovered_album.dart';
import '../models/recent_play.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../services/matching_service.dart';
import '../services/deep_link_service.dart';
import '../widgets/download_button.dart';
import '../widgets/cover_image.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/album_options_sheet.dart';
import '../widgets/artist_options_sheet.dart';
import '../widgets/bottom_sheet_common.dart';
import '../widgets/bottom_bar_reserve.dart';

class AlbumScreen extends StatefulWidget {
  final Album album;
  final String? filterArtist;
  // Fait defiler automatiquement jusqu'a ce titre a l'ouverture -- utilise
  // par le big-player (tap sur le titre en cours) pour ne pas laisser
  // l'utilisateur chercher manuellement le titre dans un album long.
  final String? scrollToTrackId;
  const AlbumScreen(
      {super.key,
      required this.album,
      this.filterArtist,
      this.scrollToTrackId});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  // Position de defilement par album (id -> offset), conservee pour la duree
  // de la session -- restauree a la reouverture d'un album deja visite au
  // lieu de systematiquement remonter en haut (retour utilisateur). Meme
  // pattern que le cache Deezer statique de ArtistScreen.
  static final Map<String, double> _savedScrollOffsets = {};

  Color? _dominantColor;
  late final ScrollController _scrollController;
  double _scrollOffset = 0;
  final _discovery = DiscoveryService();
  final _downloadWorker = DownloadWorkerService();
  List<DiscoveredTrack> _discoveredTracks = [];
  // Reste a false le temps du tout premier chargement pour ne montrer ni les
  // titres locaux seuls ni une liste incomplete avant d'avoir la reponse
  // Deezer complete (evite le "flash" 4 titres -> 16 titres). Les
  // rechargements suivants (fin de synchro) ne remettent pas ce flag a false
  // -- meme logique que DesktopAlbumView.
  bool _hasLoadedOnce = false;
  final Map<int, DownloadUiState> _downloadStates = {};

  AppState? _appState;
  bool _wasSyncing = false;

  // Cle du titre cible de widget.scrollToTrackId, assignee a sa tuile des
  // qu'elle est construite pour pouvoir la faire defiler dans la vue une
  // fois trouvee (Scrollable.ensureVisible).
  GlobalKey? _scrollTargetKey;
  bool _didScrollToTarget = false;

  @override
  void initState() {
    super.initState();
    _scrollOffset = _savedScrollOffsets[widget.album.id] ?? 0;
    _scrollController = ScrollController(initialScrollOffset: _scrollOffset);
    _extractColor();
    _loadDeezerTracks();
    _scrollController.addListener(() {
      if (!mounted) return;
      final newOffset = _scrollController.offset;
      _savedScrollOffsets[widget.album.id] = newOffset;
      // Ne redessine (recalcule aussi la tracklist de l'album, potentiellement
      // couteux sur une grosse bibliotheque) que si l'opacite affichee de
      // l'AppBar change vraiment -- en dehors de la bande de transition de
      // 80px, elle reste figee a 0 ou 1 quel que soit le defilement, inutile
      // de reconstruire tout l'ecran a chaque pixel scrolle.
      final changed =
          _appBarOpacity(newOffset) != _appBarOpacity(_scrollOffset);
      _scrollOffset = newOffset;
      if (changed) setState(() {});
    });
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

  /// Si cette page a ete ouverte pendant une synchro NAS en cours, le statut
  /// "possede" calcule alors serait fige et faux pour le reste de la session
  /// -- on recharge une fois la synchro terminee. Meme logique que
  /// DesktopAlbumView.
  void _onAppStateChanged() {
    final syncing = _appState?.isSyncing ?? false;
    if (_wasSyncing && !syncing && mounted) {
      _loadDeezerTracks();
    }
    _wasSyncing = syncing;
  }

  double _appBarOpacity(double offset) => ((offset - 320) / 80).clamp(0.0, 1.0);

  void _maybeScrollToTarget() {
    if (_didScrollToTarget || !mounted) return;
    final ctx = _scrollTargetKey?.currentContext;
    if (ctx == null) return; // pas encore construit (chargement en cours)
    _didScrollToTarget = true;
    Scrollable.ensureVisible(ctx,
        alignment: 0.3,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _appState?.removeListener(_onAppStateChanged);
    _scrollController.dispose();
    super.dispose();
  }

  /// Meme algorithme que AppState._extractDominantColorIsolate : la swatch
  /// "vibrant" de PaletteGenerator (deja une dependance du projet) plutot
  /// qu'une moyenne brute de quelques pixels, qui produisait une couleur
  /// "boueuse" ne representant pas vraiment la cover.
  Future<void> _extractColor() async {
    final path = widget.album.coverPath;
    if (path == null) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        FileImage(File(path)),
        size: const Size(100, 100),
      );
      final color = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.mutedColor?.color;
      if (mounted) setState(() => _dominantColor = color);
    } catch (_) {}
  }

  Future<void> _loadDeezerTracks() async {
    try {
      final albums =
          await _discovery.searchAlbums(widget.album.title, limit: 10);
      DiscoveredAlbum? match;
      for (final a in albums) {
        if (MatchingService.artistsMatch(a.artistName, widget.album.artist) &&
            MatchingService.albumsMatch(a.title, widget.album.title)) {
          match = a;
          break;
        }
      }
      if (match != null) {
        final tracks = await _discovery.getAlbumTracks(match.id);
        if (mounted) setState(() => _discoveredTracks = tracks);
      }
    } catch (e) {
      debugPrint('Deezer album tracks error: $e');
    }
    if (mounted) setState(() => _hasLoadedOnce = true);
  }

  /// Demande le telechargement automatique d'un titre absent du NAS (voir
  /// DownloadWorkerService) -- meme logique que DesktopAlbumView, jusqu'ici
  /// jamais branchee cote mobile (retour utilisateur).
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

  /// Fusionne les pistes locales par titre normalise (garde la version likee
  /// si le NAS a deux fois le meme morceau range dans cet album) : evite
  /// qu'un titre apparaisse deux fois (une fois like, une fois non-like).
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
  /// contenu de reference) : pour chaque titre, on cherche juste s'il existe
  /// en local (blanc/like) ou non (grise). Les pistes locales qu'on possede
  /// mais qui ne sont pas dans le tracklist Deezer (bonus...) sont ajoutees
  /// a la suite.
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

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // Match exact par id (widget.album.trackIds, deja assemble correctement
    // par MusicService.rebuildAlbums) plutot que par similarite floue de
    // titre : MatchingService.albumsMatch est concu pour rapprocher un album
    // local d'un resultat de recherche en ligne (Deezer) malgre de petites
    // variations de titre, pas pour filtrer toute la bibliotheque -- un
    // titre d'album court/generique pouvait y matcher un album totalement
    // different (ex: "99" matchant "99 Nights (Edition Deluxe)" par simple
    // inclusion de sous-chaine), en plus de recalculer cette similarite sur
    // toute la bibliotheque a chaque frame de scroll (retour utilisateur :
    // page tres lente, titres d'un autre artiste en fin de liste).
    final albumTrackIds = widget.album.trackIds.toSet();
    var albumTracks = appState.allTracks
        .where((t) => albumTrackIds.contains(t.id))
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    if (widget.filterArtist != null) {
      bool artistMatch(String? artistField) =>
          MatchingService.artistFieldContains(
              artistField, widget.filterArtist!);

      albumTracks = albumTracks
          .where((t) => artistMatch(t.artist) || artistMatch(t.albumArtist))
          .toList();
    }

    albumTracks = _dedupByTitle(albumTracks);
    final items = _buildTrackList(albumTracks);

    if (widget.scrollToTrackId != null && !_didScrollToTarget) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeScrollToTarget());
    }

    final topColor = _dominantColor != null
        ? Color.lerp(_dominantColor, Colors.black, 0.25)!
        : const Color(0xFF121212);
    final appBarColor = _dominantColor != null
        ? Color.lerp(_dominantColor, Colors.black, 0.35)!
        : const Color(0xFF121212);

    final appBarOpacity = _appBarOpacity(_scrollOffset);

    return Scaffold(
      // Transparent (pas un solide 0xFF121212) : cette page est toujours
      // ouverte en overlay AppState (jamais une vraie route Navigator.push),
      // donc deja au-dessus du fond partage de l'app (AppBackground, choisi
      // dans Parametres > Personnalisation) -- un fond opaque ici l'aurait
      // completement masque, contrairement a la home ou a la page artiste
      // (retour utilisateur : pages album pas assorties au reste de l'app).
      // Le degrade ci-dessous ne fait plus que teinter ce fond partage avec
      // la couleur dominante de la cover, sans jamais redevenir opaque.
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [topColor.withOpacity(0.6), Colors.transparent],
            stops: const [0.0, 0.45],
          ),
        ),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: appBarOpacity == 0
                  ? Colors.transparent
                  : appBarColor.withOpacity(appBarOpacity),
              elevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              forceElevated: false,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => appState.popOverlay(),
              ),
              title: Opacity(
                opacity: appBarOpacity,
                child: Text(
                  widget.album.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child:
                  _buildHeader(albumTracks, appState, totalCount: items.length),
            ),
            SliverToBoxAdapter(
              child: _buildActionBar(albumTracks, appState),
            ),
            if (!_hasLoadedOnce)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => const _SkeletonTrackRow(),
                    childCount: albumTracks.length.clamp(1, 8),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = items[index];
                      if (item.localTrack != null) {
                        final track = item.localTrack!;
                        final isScrollTarget = !_didScrollToTarget &&
                            track.id == widget.scrollToTrackId;
                        if (isScrollTarget) {
                          _scrollTargetKey ??= GlobalKey();
                        }
                        return _AlbumTrackTile(
                          key: isScrollTarget ? _scrollTargetKey : null,
                          index: index,
                          track: track,
                          isPlaying: appState.currentTrack?.id == track.id,
                          onTap: () {
                            _recordRecent(appState);
                            appState.playTrack(track, trackList: albumTracks);
                          },
                          onLike: () => appState.toggleLike(track.id),
                          onMore: () => _showTrackOptions(context, track),
                        );
                      } else {
                        final dt = item.discoveredTrack!;
                        return _DiscoveredTrackTile(
                          index: index,
                          track: dt,
                          downloadState: _downloadStates[dt.id],
                          showDownloadButton: _downloadWorker.isConfigured,
                          onDownloadTap: () => _downloadTrack(dt),
                        );
                      }
                    },
                    childCount: items.length,
                  ),
                ),
              ),
            SliverToBoxAdapter(
                child: SizedBox(height: bottomBarReserve(context))),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(List<Track> tracks, AppState state, {int? totalCount}) {
    final coverPath = widget.album.coverPath;
    final exists = state.coverExists(coverPath);
    final screenWidth = MediaQuery.of(context).size.width;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: screenWidth * 0.60,
              height: screenWidth * 0.60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
                image: exists && coverPath != null
                    ? DecorationImage(
                        image: coverImageProvider(context,
                            path: coverPath,
                            width: screenWidth * 0.60,
                            height: screenWidth * 0.60),
                        fit: BoxFit.cover,
                        onError: (_, __) {},
                      )
                    : null,
                color: const Color(0xFF2A2A2A),
              ),
              child: !exists || coverPath == null
                  ? const Icon(Icons.album, color: Colors.white54, size: 64)
                  : null,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            widget.album.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              showArtistPicker(context, widget.album.artist);
            },
            child: Row(
              children: [
                ArtistAvatar(
                  artistName: widget.album.artist,
                  fallbackCoverPath: widget.album.coverPath,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.album.artist,
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
            'Album • ${totalCount ?? tracks.length} titres',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(List<Track> tracks, AppState state) {
    final isLiked = widget.album.isSaved;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 16, 16),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              color: isLiked ? const Color(0xFF1DB954) : Colors.white54,
            ),
            onPressed: () => state.toggleLikeAlbum(widget.album.id),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.white54),
            onPressed: () {
              if (tracks.isNotEmpty) {
                _showAddToPlaylistDialog(context, tracks.first);
              }
            },
          ),
          DownloadButton(
            tracks: tracks,
            idleColor: Colors.white54,
            confirmDeleteMessage:
                'Cet album ne sera plus disponible hors connexion.',
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white54),
            onPressed: () => showAlbumOptions(context, widget.album),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.shuffle, color: Colors.white54, size: 26),
            onPressed: () {
              if (tracks.isNotEmpty) {
                _recordRecent(state);
                final shuffled = List<Track>.of(tracks)..shuffle();
                state.playTrack(shuffled.first, trackList: shuffled);
              }
            },
          ),
          const SizedBox(width: 4),
          _PlayPauseButton(album: widget.album, albumTracks: tracks),
        ],
      ),
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, Track track) {
    final state = context.read<AppState>();
    final playlists = state.playlists;

    if (playlists.isEmpty) {
      _showSnack("Aucune playlist. Creez-en une d'abord.");
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Ajouter a une playlist',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: playlists.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(playlists[i].name,
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                state.addToPlaylist(playlists[i].id, track.id);
                Navigator.pop(ctx);
                _showSnack('Ajoute a ${playlists[i].name}');
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _showTrackOptions(BuildContext context, Track track) {
    final state = context.read<AppState>();
    showOptionsSheet(context,
        builder: (ctx) => [
              BottomSheetHeader(
                coverPath: track.coverPath,
                title: track.title,
                subtitle: track.artist,
              ),
              const Divider(color: Color(0xFF2A2A2A), height: 1),
              SheetTile(
                icon: Icons.add_circle_outline,
                label: 'Ajouter a la playlist',
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddToPlaylistDialog(context, track);
                },
              ),
              SheetTile(
                icon: Icons.playlist_play,
                label: 'Lire ensuite',
                onTap: () {
                  Navigator.pop(ctx);
                  state.playNext(track);
                  _showSnack('"${track.title}" sera joue ensuite');
                },
              ),
              SheetTile(
                icon: Icons.playlist_add,
                label: "Ajouter a la file d'attente",
                onTap: () {
                  Navigator.pop(ctx);
                  state.addToQueue(track);
                  _showSnack('"${track.title}" ajoute a la file');
                },
              ),
              SheetTile(
                icon: Icons.album_outlined,
                label: "Acceder a l'album",
                onTap: () => Navigator.pop(ctx),
              ),
              SheetTile(
                icon: Icons.person_outline,
                label: "Acceder a l'artiste",
                onTap: () {
                  Navigator.pop(ctx);
                  showArtistPicker(context, track.artist);
                },
              ),
              SheetTile(
                icon: track.isLiked ? Icons.favorite : Icons.favorite_border,
                label: track.isLiked
                    ? 'Retirer des titres likes'
                    : 'Ajouter aux titres likes',
                iconColor:
                    track.isLiked ? const Color(0xFF1DB954) : Colors.white,
                onTap: () {
                  Navigator.pop(ctx);
                  state.toggleLike(track.id);
                },
              ),
              SheetTile(
                icon: Icons.ios_share,
                label: 'Partager',
                onTap: () {
                  Navigator.pop(ctx);
                  shareTrack(track);
                },
              ),
              if (state.shareInboxConfigured)
                SheetTile(
                  icon: Icons.send_outlined,
                  label: 'Envoyer a un ami',
                  onTap: () {
                    Navigator.pop(ctx);
                    showSendToFriendDialog(context,
                        type: 'track',
                        itemId: track.id,
                        title: track.title,
                        subtitle: track.artist);
                  },
                ),
              const SizedBox(height: 8),
            ]);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF2A2A2A),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
/// temps d'avoir la tracklist complete a montrer d'un coup -- meme widget
/// que DesktopAlbumView.
class _SkeletonTrackRow extends StatelessWidget {
  const _SkeletonTrackRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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

class _PlayPauseButton extends StatelessWidget {
  final Album album;
  final List<Track> albumTracks;
  const _PlayPauseButton({required this.album, required this.albumTracks});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (bool, bool)>(
      selector: (_, state) {
        final isThisAlbum = state.currentTrack != null &&
            albumTracks.any((t) => t.id == state.currentTrack!.id);
        return (isThisAlbum, state.isPlaying);
      },
      builder: (context, data, _) {
        final (isThisAlbum, isPlaying) = data;
        final isPlayingThisAlbum = isThisAlbum && isPlaying;

        return GestureDetector(
          onTap: () {
            final state = context.read<AppState>();
            if (isPlayingThisAlbum) {
              state.togglePlayPause();
            } else if (albumTracks.isNotEmpty) {
              state.recordRecentPlay(RecentPlay(
                type: RecentPlayType.album,
                id: album.id,
                title: album.title,
                subtitle: album.artist,
                coverPath: album.coverPath,
                playedAt: DateTime.now(),
              ));
              state.playTrack(albumTracks.first, trackList: albumTracks);
            }
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xFF1DB954),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              isPlayingThisAlbum ? Icons.pause : Icons.play_arrow,
              color: Colors.black,
              size: 32,
            ),
          ),
        );
      },
    );
  }
}

class _AlbumTrackTile extends StatelessWidget {
  final int index;
  final Track track;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onMore;
  final bool isPlaying;

  const _AlbumTrackTile({
    super.key,
    required this.index,
    required this.track,
    required this.onTap,
    required this.onLike,
    required this.onMore,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: isPlaying
                  ? const Icon(Icons.graphic_eq,
                      color: Color(0xFF1DB954), size: 16)
                  : Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white54,
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
                      color: isPlaying ? const Color(0xFF1DB954) : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.artist,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (track.isLiked)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.favorite,
                  color: const Color(0xFF1DB954),
                  size: 16,
                ),
              ),
            IconButton(
              icon:
                  const Icon(Icons.more_vert, color: Colors.white54, size: 20),
              onPressed: onMore,
              splashRadius: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveredTrackTile extends StatelessWidget {
  final int index;
  final DiscoveredTrack track;
  final DownloadUiState? downloadState;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;

  const _DiscoveredTrackTile({
    required this.index,
    required this.track,
    required this.downloadState,
    required this.showDownloadButton,
    required this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white24,
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
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.artistName,
                    style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 12,
                    ),
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
            ),
          ],
        ),
      ),
    );
  }
}
