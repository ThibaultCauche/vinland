import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/discovered_album.dart';
import '../models/discovered_artist.dart';
import '../models/discovered_track.dart';
import '../models/pinned_item.dart';
import '../models/recent_play.dart';
import '../models/track.dart';
import '../services/artist_discography.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../services/matching_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/download_button.dart';
import 'desktop_hero_card.dart'
    show DesktopHeroMenuAction, DesktopMoreMenuButton, trackMoreMenuActions;
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
  final void Function(Album album, {String? filterArtist}) onOpenAlbum;
  final void Function(
      {DiscoveredAlbum? album,
      int? albumId,
      String? filterArtist}) onOpenDiscoveredAlbum;
  final void Function(String artistName) onOpenDiscography;

  const DesktopArtistView({
    super.key,
    required this.artistName,
    required this.onOpenAlbum,
    required this.onOpenDiscoveredAlbum,
    required this.onOpenDiscography,
  });

  @override
  State<DesktopArtistView> createState() => _DesktopArtistViewState();
}

class _DesktopArtistViewState extends State<DesktopArtistView> {
  static final Map<String, _ArtistCache> _deezerCache = {};
  final _discovery = DiscoveryService();
  final _downloadWorker = DownloadWorkerService();
  final Map<int, DownloadUiState> _downloadStates = {};

  DiscoveredArtist? _discoveredArtist;
  List<DiscoveredAlbum> _discoveredAlbums = [];
  List<DiscoveredTrack> _topTracks = [];
  bool _loadingDeezer = true;
  bool _loadingTopTracks = true;
  final _scrollController = SmoothScrollController();

  // Nombre de titres reel par album Deezer (id -> nb_tracks), pour les
  // albums locaux : l'endpoint liste des albums d'un artiste ne renvoie pas
  // ce champ (contrairement a /album/{id} ou /search/album), donc on le
  // recupere a part pour ne pas afficher le nombre de titres deja
  // telecharges comme s'il s'agissait du total de l'album.
  final Map<int, int> _trueTrackCounts = {};

  AppState? _appState;
  bool _wasSyncing = false;

  @override
  void dispose() {
    _appState?.removeListener(_onAppStateChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final cached = _deezerCache[MatchingService.normalize(widget.artistName)];
    if (cached != null) {
      _discoveredArtist = cached.artist;
      _discoveredAlbums = cached.albums;
      _topTracks = cached.topTracks;
      _loadingDeezer = false;
      _loadingTopTracks = false;
      if (!cached.deepMatched) _deepMatchAlbums();
      _loadTrueTrackCounts();
    } else {
      _loadDeezerData();
    }
  }

  /// Complete le nombre de titres des albums locaux qui ont une
  /// correspondance Deezer, via l'endpoint album unique (leger : pas besoin
  /// de la tracklist complete, juste nb_tracks). Servi par le cache disque
  /// de DiscoveryService, donc peu couteux meme rappele a chaque ouverture.
  Future<void> _loadTrueTrackCounts() async {
    final targets = _discoveredAlbums
        .where((a) => a.isInLibrary && !_trueTrackCounts.containsKey(a.id))
        .toList();
    if (targets.isEmpty) return;

    const batchSize = 5;
    for (var i = 0; i < targets.length; i += batchSize) {
      final batch = targets.skip(i).take(batchSize);
      await Future.wait(batch.map((a) async {
        final full = await _discovery.getAlbum(a.id);
        if (full?.nbTracks != null) _trueTrackCounts[a.id] = full!.nbTracks!;
      }));
      if (mounted) setState(() {});
    }
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

  /// Si cette page a ete ouverte pendant que la bibliotheque NAS finissait
  /// encore de charger, le statut "possede" calcule alors (isInLibrary) est
  /// fige dans le cache de session et reste faux pour le reste de la
  /// session -- on relance le calcul (recherche Deezer re-servie par son
  /// propre cache disque, donc peu couteux) une fois la synchro terminee.
  void _onAppStateChanged() {
    final syncing = _appState?.isSyncing ?? false;
    if (_wasSyncing && !syncing && mounted) {
      _loadDeezerData();
    }
    _wasSyncing = syncing;
  }

  Future<void> _loadDeezerData() async {
    final data = await loadArtistDeezerData(_discovery, widget.artistName);
    _discoveredArtist = data.artist;
    _discoveredAlbums = data.albums;
    _topTracks = data.topTracks;

    if (mounted) {
      setState(() {
        _loadingDeezer = false;
        _loadingTopTracks = false;
      });
    }
    _deezerCache[MatchingService.normalize(widget.artistName)] = _ArtistCache(
      artist: _discoveredArtist,
      albums: _discoveredAlbums,
      topTracks: _topTracks,
    );
    _deepMatchAlbums();
    _loadTrueTrackCounts();
  }

  /// Demande le telechargement automatique d'un titre populaire absent du
  /// NAS (voir DownloadWorkerService) -- meme logique que DesktopAlbumView,
  /// jusqu'ici jamais branchee sur cette page (retour utilisateur). Pas
  /// besoin de recharger _topTracks apres coup : `popularTracks` (dans
  /// build()) recroise deja _topTracks avec state.allTracks a chaque
  /// reconstruction, donc syncRecentlyAdded() suffit a faire apparaitre le
  /// titre comme disponible.
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
      if (mounted) setState(() => _downloadStates.remove(track.id));
    } else {
      setState(() => _downloadStates[track.id] = DownloadUiState.failed);
    }
  }

  Future<void> _deepMatchAlbums() async {
    final state = context.read<AppState>();

    await deepMatchArtistAlbums(
      discovery: _discovery,
      discoveredAlbums: _discoveredAlbums,
      allLocalTracks: state.allTracks,
      artistName: widget.artistName,
    );

    if (mounted) {
      final key = MatchingService.normalize(widget.artistName);
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

  Track? _findLocalTrack(DiscoveredTrack dt, List<Track> candidates) {
    for (final t in candidates) {
      if (MatchingService.titlesMatch(t.title, dt.title)) return t;
    }
    return null;
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
        final tracks = tracksForArtist(state.allTracks, widget.artistName);
        final albums =
            albumsForArtist(state.albums, state.allTracks, widget.artistName);
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

        final albumEntries = buildArtistAlbumEntries(
          localAlbums: localAlbums,
          discoveredAlbums: _discoveredAlbums,
          trueTrackCounts: _trueTrackCounts,
        );

        final artistImage = _discoveredArtist?.pictureBigUrl ??
            (localAlbums.isNotEmpty ? localAlbums.first.coverPath : null);

        // topInsetCompact -- meme raison que DesktopCollectionView.
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
                        moreActions: [
                          DesktopHeroMenuAction(
                            label: state.isPinned(PinnedItemType.artist,
                                    widget.artistName)
                                ? "Désépingler de l'accueil"
                                : "Épingler à l'accueil",
                            icon: state.isPinned(PinnedItemType.artist,
                                    widget.artistName)
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            onTap: () => state.togglePin(PinnedItem(
                              type: PinnedItemType.artist,
                              id: widget.artistName,
                              title: widget.artistName,
                              subtitle: 'Artiste',
                            )),
                          ),
                        ],
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
                              downloadState: _downloadStates[
                                  popularTracks[index].discovered.id],
                              showDownloadButton: _downloadWorker.isConfigured,
                              onDownloadTap: () => _downloadTrack(
                                  popularTracks[index].discovered),
                            ),
                            childCount: popularTracks.length,
                          ),
                        ),
                      ),
                    ],
                    if (albumEntries.isNotEmpty) ...[
                      _AlbumsSectionHeader(
                        onOpenDiscography: () =>
                            widget.onOpenDiscography(widget.artistName),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        sliver: SliverToBoxAdapter(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              const maxExtent = 170.0;
                              const spacing = 14.0;
                              final columns = ((constraints.maxWidth +
                                          spacing) /
                                      (maxExtent + spacing))
                                  .floor()
                                  .clamp(1, albumEntries.length);
                              final shown =
                                  albumEntries.take(columns).toList();
                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: maxExtent,
                                  childAspectRatio: 0.72,
                                  crossAxisSpacing: spacing,
                                  mainAxisSpacing: 18,
                                ),
                                itemCount: shown.length,
                                itemBuilder: (context, index) {
                                  final entry = shown[index];
                                  if (entry.local != null) {
                                    return _LocalAlbumCard(
                                      album: entry.local!,
                                      artistName: widget.artistName,
                                      totalTrackCount:
                                          entry.knownTotalTrackCount,
                                      onTap: () => widget.onOpenAlbum(
                                          entry.local!,
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
                              );
                            },
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

/// En-tete de la section "Albums" : titre + bouton "Discographie" pour voir
/// la liste complete -- la grille elle-meme n'affiche qu'une seule rangee
/// (voir LayoutBuilder ci-dessus), le reste de la discographie de l'artiste
/// n'est visible qu'via cette page dediee (retour utilisateur : la page
/// artiste devenait trop chargee a afficher tous les albums d'un coup).
class _AlbumsSectionHeader extends StatelessWidget {
  final VoidCallback onOpenDiscography;
  const _AlbumsSectionHeader({required this.onOpenDiscography});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
        child: Row(
          children: [
            const Expanded(
              child: Text('Albums',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: onOpenDiscography,
              child: const Text('Discographie',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
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
  final List<DesktopHeroMenuAction> moreActions;

  const _Header({
    required this.artistName,
    required this.artistImage,
    required this.localTrackCount,
    required this.deezerAlbumCount,
    required this.onPlay,
    required this.onShuffle,
    this.moreActions = const [],
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
      ),
    );
  }
}

class _PopularTrackRow extends StatelessWidget {
  final int index;
  final _PopularTrack track;
  final VoidCallback onPlay;
  final DownloadUiState? downloadState;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;

  const _PopularTrackRow({
    required this.index,
    required this.track,
    required this.onPlay,
    required this.downloadState,
    required this.showDownloadButton,
    required this.onDownloadTap,
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
            if (isAvailable) ...[
              // Like puis "..." (lire ensuite, file d'attente, partager,
              // envoyer a un ami) -- l'icone de lecture separee etait
              // redondante avec le tap sur toute la ligne (onPlay
              // ci-dessus), remplacee par le like comme sur les autres
              // listes de titres (retour utilisateur). Seulement quand le
              // titre est deja sur le NAS (track.local) : rien a liker/mettre
              // en file d'attente pour un titre pas encore telecharge.
              GlassIconButton(
                icon: track.local!.isLiked
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: track.local!.isLiked
                    ? DesktopGlass.accent
                    : Colors.white54,
                size: 18,
                onPressed: () =>
                    context.read<AppState>().toggleLike(track.local!.id),
              ),
              const SizedBox(width: 4),
              DesktopMoreMenuButton(
                actions: trackMoreMenuActions(
                    context, context.read<AppState>(), track.local!),
              ),
            ] else
              DownloadStateIcon(
                state: downloadState,
                showDownloadButton: showDownloadButton,
                onDownloadTap: onDownloadTap,
                size: 18,
              ),
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
  // Nombre de titres reel de l'album cote Deezer, quand connu -- affiche a
  // la place du nombre de titres deja telecharges pour un album seulement
  // partiellement possede (sinon la vignette laisse croire que l'album
  // entier ne fait que N titres).
  final int? totalTrackCount;

  const _LocalAlbumCard({
    required this.album,
    required this.artistName,
    required this.onTap,
    this.compact = false,
    this.totalTrackCount,
  });

  @override
  Widget build(BuildContext context) {
    final trackCount = totalTrackCount ?? album.trackIds.length;

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
