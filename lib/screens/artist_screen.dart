import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/discovered_album.dart';
import '../models/discovered_artist.dart';
import '../models/discovered_track.dart';
import '../models/recent_play.dart';
import '../services/artist_discography.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../services/matching_service.dart';
import '../widgets/download_button.dart';
import '../widgets/track_tile.dart';
import '../widgets/cover_image.dart';
import '../widgets/artist_options_sheet.dart';
import '../widgets/bottom_bar_reserve.dart';
import '../widgets/player/player_options_sheet.dart';
import 'album_screen.dart';
import 'artist_discography_screen.dart';
import 'discovered_album_screen.dart';

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

class ArtistScreen extends StatefulWidget {
  final String artistName;

  const ArtistScreen({super.key, required this.artistName});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  static final Map<String, _ArtistCache> _deezerCache = {};
  // Position de defilement par artiste, conservee pour la duree de la
  // session -- restauree a la reouverture d'une page artiste deja visitee
  // au lieu de systematiquement remonter en haut (retour utilisateur). Meme
  // pattern que _deezerCache ci-dessus.
  static final Map<String, double> _savedScrollOffsets = {};

  final _discovery = DiscoveryService();
  final _downloadWorker = DownloadWorkerService();
  final Map<int, DownloadUiState> _downloadStates = {};
  late final ScrollController _scrollController;

  DiscoveredArtist? _discoveredArtist;
  List<DiscoveredAlbum> _discoveredAlbums = [];
  List<DiscoveredTrack> _topTracks = [];
  bool _loadingDeezer = true;
  bool _deepMatching = false;
  bool _loadingTopTracks = true;
  int _deepMatchProgress = 0;
  int _deepMatchTotal = 0;

  // Nombre de titres reel par album Deezer (id -> nb_tracks) : l'endpoint
  // liste des albums d'un artiste ne renvoie pas ce champ (contrairement a
  // /album/{id} ou /search/album), donc on le recupere a part pour ne pas
  // afficher le nombre de titres deja telecharges comme total de l'album.
  final Map<int, int> _trueTrackCounts = {};

  AppState? _appState;
  bool _wasSyncing = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
        initialScrollOffset: _savedScrollOffsets[widget.artistName] ?? 0);
    _scrollController.addListener(() {
      _savedScrollOffsets[widget.artistName] = _scrollController.offset;
    });
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
  /// session -- on relance le calcul une fois la synchro terminee. Meme
  /// logique que DesktopArtistView.
  void _onAppStateChanged() {
    final syncing = _appState?.isSyncing ?? false;
    if (_wasSyncing && !syncing && mounted) {
      _loadDeezerData();
    }
    _wasSyncing = syncing;
  }

  @override
  void dispose() {
    _appState?.removeListener(_onAppStateChanged);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTrueTrackCounts() async {
    final targets = _discoveredAlbums
        .where((a) => a.isInLibrary && !_trueTrackCounts.containsKey(a.id))
        .toList();
    if (targets.isEmpty) return;

    // Un seul setState a la toute fin, pas un par lot : ce nombre de titres
    // n'alimente qu'un petit label cosmetique sur chaque carte d'album, rien
    // qui justifie de re-render toute la page (tri/filtrage des sections
    // Albums/Singles, matching des titres populaires...) plusieurs fois de
    // suite pendant le chargement -- sur un artiste avec beaucoup d'albums,
    // ces reconstructions repetees rendaient la page saccadee et peu
    // reactive au scroll le temps du chargement (retour utilisateur).
    const batchSize = 5;
    for (var i = 0; i < targets.length; i += batchSize) {
      final batch = targets.skip(i).take(batchSize);
      await Future.wait(batch.map((a) async {
        final full = await _discovery.getAlbum(a.id);
        if (full?.nbTracks != null) _trueTrackCounts[a.id] = full!.nbTracks!;
      }));
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadDeezerData() async {
    final data = await loadArtistDeezerData(_discovery, widget.artistName);
    _discoveredArtist = data.artist;
    _discoveredAlbums = data.albums;
    _topTracks = data.topTracks;

    if (mounted)
      setState(() {
        _loadingDeezer = false;
        _loadingTopTracks = false; // ← ici, APRÈS le Future.wait
      });
    _deezerCache[MatchingService.normalize(widget.artistName)] = _ArtistCache(
      artist: _discoveredArtist,
      albums: _discoveredAlbums,
      topTracks: _topTracks,
    );
    _deepMatchAlbums();
    _loadTrueTrackCounts();
  }

  /// Demande le telechargement automatique d'un titre populaire absent du
  /// NAS (voir DownloadWorkerService) -- meme logique que AlbumScreen,
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

    // Ne verifie que les albums susceptibles d'apparaitre dans l'apercu (4
    // affiches ici, voir shownAlbumEntries) plutot que toute la
    // discographie Deezer (jusqu'a plusieurs dizaines d'albums) -- retour
    // utilisateur : verification/chargement inutilement lourds pour une
    // page qui n'en montre que 4. Marge (12 au lieu de 4) pour absorber les
    // changements d'ordre au fur et a mesure que des albums basculent de
    // "decouvert" a "possede" pendant la verification. La page
    // Discographie fait sa propre verification complete independamment
    // (voir ArtistDiscographyScreen), donc rien n'y manquera.
    final (_, localAlbums) = _artistTracksAndAlbums(state);
    final previewCandidates = buildArtistAlbumEntries(
      localAlbums: localAlbums,
      discoveredAlbums: _discoveredAlbums,
      trueTrackCounts: _trueTrackCounts,
    ).take(12).map((e) => e.discovered).whereType<DiscoveredAlbum>().toList();

    final unmatchedTotal =
        previewCandidates.where((a) => !a.isInLibrary).length;
    if (unmatchedTotal == 0) return;

    if (mounted) {
      setState(() {
        _deepMatching = true;
        _deepMatchTotal = unmatchedTotal;
        _deepMatchProgress = 0;
      });
    }

    // setState() ici recalcule aussi tracks/albums de tout l'artiste (voir
    // le selector de build(), qui rescanne toute la bibliotheque locale) --
    // un artiste avec beaucoup d'albums non-matches declenchait un
    // setState() par lot de 5, donc un rescan complet toutes les quelques
    // requetes reseau : page saccadee et scroll qui ne repondait plus le
    // temps du chargement (retour utilisateur). On garde la mise a jour
    // progressive (versus tout a la fin), juste moins frequente --
    // ponytail: throttle naif base sur le temps, pas de debounce propre,
    // suffisant ici puisque la derniere iteration force toujours une mise a
    // jour finale.
    var lastUiUpdate = DateTime.now();
    await deepMatchArtistAlbums(
      discovery: _discovery,
      discoveredAlbums: previewCandidates,
      allLocalTracks: state.allTracks,
      artistName: widget.artistName,
      onProgress: (completed, total) {
        final isLast = completed >= total;
        final now = DateTime.now();
        if (mounted &&
            (isLast ||
                now.difference(lastUiUpdate) >
                    const Duration(milliseconds: 400))) {
          lastUiUpdate = now;
          setState(() => _deepMatchProgress = completed);
        }
      },
    );

    if (mounted) {
      setState(() {
        _deepMatching = false;
        final key = MatchingService.normalize(widget.artistName);
        if (_deezerCache.containsKey(key)) {
          _deezerCache[key] = _ArtistCache(
            artist: _discoveredArtist,
            albums: _discoveredAlbums,
            topTracks: _topTracks,
            deepMatched: true,
          );
        }
      });
    }
  }

  /// Trouve la track locale correspondant a une track Deezer
  Track? _findLocalTrack(DiscoveredTrack dt, List<Track> candidates) {
    for (final t in candidates) {
      if (MatchingService.titlesMatch(t.title, dt.title)) return t;
    }
    return null;
  }

  // Memoise le resultat du filtrage artiste (state.allTracks/albums,
  // MusicService.navidromeTracks/albums, sont des vues mises en cache : la
  // meme instance de List tant que la bibliotheque locale n'a pas vraiment
  // change -- voir les getters correspondants dans music_service.dart) au
  // lieu de rescanner toute la bibliotheque (potentiellement des milliers de
  // titres) a CHAQUE rebuild de cet ecran. Cet ecran declenche beaucoup de
  // setState() locaux pendant son chargement (progression du deep-match
  // Deezer...), qui ne touchent jamais allTracks/albums -- sans ce cache, un
  // gros artiste avec beaucoup d'albums rendait la page saccadee et peu
  // reactive au scroll tout le temps du chargement (retour utilisateur).
  List<Track>? _matchCacheTracksInput;
  List<Album>? _matchCacheAlbumsInput;
  (List<Track>, List<Album>)? _matchCacheResult;

  (List<Track>, List<Album>) _artistTracksAndAlbums(AppState state) {
    if (identical(state.allTracks, _matchCacheTracksInput) &&
        identical(state.albums, _matchCacheAlbumsInput)) {
      return _matchCacheResult!;
    }

    final tracks = tracksForArtist(state.allTracks, widget.artistName);
    final albums =
        albumsForArtist(state.albums, state.allTracks, widget.artistName);

    _matchCacheTracksInput = state.allTracks;
    _matchCacheAlbumsInput = state.albums;
    _matchCacheResult = (tracks, albums);
    return _matchCacheResult!;
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
      selector: (_, state) => _artistTracksAndAlbums(state),
      builder: (context, data, child) {
        final (allArtistTracks, localAlbums) = data;
        final state = context.read<AppState>();

        // Match les top tracks Deezer avec les tracks locales
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
        // Un maximum de 4 albums (2x2) sur la page artiste, le reste (et le
        // tracklist complet de chaque album) n'est visible que sur la page
        // "Discographie" dediee -- sinon la page artiste devenait trop
        // chargee a afficher tous les albums d'un coup (retour utilisateur).
        final shownAlbumEntries = albumEntries.take(4).toList();

        final artistImage = _discoveredArtist?.pictureBigUrl ??
            (localAlbums.isNotEmpty ? localAlbums.first.coverPath : null);

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => state.popOverlay(),
            ),
            title: Text(widget.artistName,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () => showArtistOptions(context, widget.artistName,
                    coverPath: artistImage),
              ),
            ],
          ),
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // HEADER
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _ArtistAvatar(url: artistImage),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.artistName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${allArtistTracks.length} titres locaux',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 14),
                            ),
                            if (_discoveredAlbums.isNotEmpty)
                              Text(
                                '${_discoveredAlbums.length} albums sur Deezer',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ACTIONS
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          if (allArtistTracks.isNotEmpty) {
                            _recordRecent(state, coverPath: artistImage);
                            state.playTrack(allArtistTracks.first,
                                trackList: allArtistTracks);
                          }
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Lecture'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DB954),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.shuffle, color: Colors.white),
                        onPressed: () {
                          if (allArtistTracks.isNotEmpty) {
                            _recordRecent(state, coverPath: artistImage);
                            final shuffled = List.of(allArtistTracks)
                              ..shuffle();
                            state.playTrack(shuffled.first,
                                trackList: shuffled);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // TITRES POPULAIRES (depuis Deezer)
              if (_loadingTopTracks) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Text('Titres populaires',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _SkeletonPopularTile(index: index),
                      childCount: 5,
                    ),
                  ),
                ),
              ] else if (popularTracks.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Text('Titres populaires',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _PopularTrackTile(
                        index: index,
                        track: popularTracks[index],
                        onPlay: () {
                          if (popularTracks[index].local != null) {
                            _recordRecent(state, coverPath: artistImage);
                            state.playTrack(popularTracks[index].local!);
                          }
                        },
                        downloadState:
                            _downloadStates[popularTracks[index].discovered.id],
                        showDownloadButton: _downloadWorker.isConfigured,
                        onDownloadTap: () =>
                            _downloadTrack(popularTracks[index].discovered),
                      ),
                      childCount: popularTracks.length,
                    ),
                  ),
                ),
              ],

              // ALBUMS (max 4 aperçu, le reste sur la page Discographie)
              if (shownAlbumEntries.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Row(
                      children: [
                        const Text(
                          'Albums',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_deepMatching) ...[
                          const SizedBox(width: 12),
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white38,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Vérification $_deepMatchProgress/$_deepMatchTotal',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                        ],
                        const Spacer(),
                        TextButton(
                          onPressed: () => state.pushOverlay(
                              ArtistDiscographyScreen(
                                  artistName: widget.artistName)),
                          child: const Text('Discographie',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final entry = shownAlbumEntries[index];
                        if (entry.local != null) {
                          return _LocalAlbumCard(
                            album: entry.local!,
                            state: state,
                            artistName: widget.artistName,
                            totalTrackCount: entry.knownTotalTrackCount,
                          );
                        } else {
                          return _DiscoveredAlbumCard(
                            album: entry.discovered!,
                            state: state,
                            artistName: widget.artistName,
                          );
                        }
                      },
                      childCount: shownAlbumEntries.length,
                    ),
                  ),
                ),
              ] else if (_loadingDeezer) ...[
                const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child:
                          CircularProgressIndicator(color: Color(0xFF1DB954)),
                    ),
                  ),
                ),
              ],

              // DANS LE NAS (titres locaux, distincts des "Titres populaires"
              // Deezer qui peuvent ne pas etre possedes -- voir DownloadStateIcon)
              if (allArtistTracks.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Text(
                      'Dans le NAS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  // Ni SliverPadding ni Padding n'acceptent de valeurs
                  // negatives (les deux s'appuient sur la meme assertion
                  // RenderPadding/RenderShiftedBox) -- la compensation du
                  // contentPadding fixe de TrackTile (16, non modifiable ici
                  // sans affecter tout le reste de l'app qui partage ce
                  // widget) se fait donc via Transform.translate, qui
                  // deplace juste le rendu sans toucher aux contraintes de
                  // layout (retour utilisateur : quelques pixels d'ecart
                  // avec "Titres populaires" plus haut).
                  padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Transform.translate(
                        offset: const Offset(8, 0),
                        child: Selector<AppState, Track?>(
                          selector: (_, s) => s.currentTrack,
                          builder: (context, currentTrack, __) => TrackTile(
                            track: allArtistTracks[index],
                            isPlaying:
                                currentTrack?.id == allArtistTracks[index].id,
                            onTap: () {
                              _recordRecent(state, coverPath: artistImage);
                              state.playTrack(allArtistTracks[index]);
                            },
                            onLike: () =>
                                state.toggleLike(allArtistTracks[index].id),
                            onMore: () => showPlayerOptions(
                                context, allArtistTracks[index]),
                          ),
                        ),
                      ),
                      childCount: allArtistTracks.length,
                    ),
                  ),
                ),
              ],

              SliverToBoxAdapter(
                  child: SizedBox(height: bottomBarReserve(context))),
            ],
          ),
        );
      },
    );
  }
}

/// Pair : track Deezer + track locale correspondante (ou null)
class _PopularTrack {
  final DiscoveredTrack discovered;
  final Track? local;
  const _PopularTrack({required this.discovered, this.local});
}

// TITRE POPULAIRE
class _PopularTrackTile extends StatelessWidget {
  final int index;
  final _PopularTrack track;
  final VoidCallback onPlay;
  final DownloadUiState? downloadState;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;

  const _PopularTrackTile({
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
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        // Marge droite reduite (8 au lieu de 16) : rapproche les icones du
        // bord sans les coller completement, sans toucher la marge gauche
        // (pochette/texte) -- retour utilisateur.
        padding: const EdgeInsets.fromLTRB(16, 10, 0, 10),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(4),
                image: track.discovered.coverUrl != null
                    ? DecorationImage(
                        image: coverImageProvider(context,
                            path: track.discovered.coverUrl!,
                            width: 48,
                            height: 48),
                        fit: BoxFit.cover,
                        onError: (_, __) {},
                      )
                    : null,
              ),
              child: track.discovered.coverUrl == null
                  ? const Icon(Icons.music_note, color: Colors.white54)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.discovered.title,
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
            // Like et "..." en IconButton standard (48x48, pas de padding
            // custom) ; DownloadStateIcon recentre dans la meme boite 48x48
            // (voir plus bas) pour tomber au meme x que le "..." -- version
            // confirmee alignee par l'utilisateur.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isAvailable)
                  // Like puis "..." (lire ensuite, file d'attente,
                  // partager...) -- l'icone de lecture separee etait
                  // redondante avec le tap sur toute la ligne (onTap
                  // ci-dessus, deja branche sur onPlay), remplacee par le
                  // like comme sur les autres listes de titres, meme logique
                  // que DesktopArtistView (retour utilisateur).
                  IconButton(
                    icon: Icon(
                      track.local!.isLiked
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: track.local!.isLiked
                          ? const Color(0xFF1DB954)
                          : Colors.white54,
                      size: 20,
                    ),
                    onPressed: () =>
                        context.read<AppState>().toggleLike(track.local!.id),
                    splashRadius: 20,
                  )
                else
                  const IconButton(
                    icon: SizedBox.shrink(),
                    onPressed: null,
                  ),
                if (isAvailable)
                  IconButton(
                    icon: const Icon(Icons.more_vert,
                        color: Colors.white54, size: 20),
                    onPressed: () => showPlayerOptions(context, track.local!),
                    splashRadius: 20,
                  )
                else
                  // DownloadStateIcon n'a qu'un padding de 4 autour de son
                  // icone (voir download_button.dart), contre les 48x48
                  // centres par defaut d'un IconButton -- recentre dans la
                  // meme boite 48x48 pour tomber exactement au meme x que le
                  // "..." (retour utilisateur : version confirmee alignee).
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: DownloadStateIcon(
                        state: downloadState,
                        showDownloadButton: showDownloadButton,
                        onDownloadTap: onDownloadTap,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// CARTE ALBUM LOCAL
class _LocalAlbumCard extends StatelessWidget {
  final Album album;
  final AppState state;
  final String artistName;
  final bool compact;
  // Nombre de titres reel de l'album cote Deezer, quand connu -- affiche a
  // la place du nombre de titres deja telecharges pour un album seulement
  // partiellement possede.
  final int? totalTrackCount;

  const _LocalAlbumCard({
    required this.album,
    required this.state,
    required this.artistName,
    this.compact = false,
    this.totalTrackCount,
  });

  @override
  Widget build(BuildContext context) {
    // album.trackIds est deja le decompte exact de cet album precis (voir
    // MusicService.rebuildAlbums) -- pas besoin de re-derouler par titre,
    // qui pouvait compter les titres d'un autre album partageant le meme
    // nom.
    final trackCount = totalTrackCount ?? album.trackIds.length;

    final cover = compact
        ? SizedBox(
            width: 120,
            height: 120,
            child: _AlbumCover(coverPath: album.coverPath),
          )
        : Expanded(child: _AlbumCover(coverPath: album.coverPath));

    final card = GestureDetector(
      onTap: () => state
          .pushOverlay(AlbumScreen(album: album, filterArtist: artistName)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          cover,
          const SizedBox(height: 8),
          Text(
            album.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            compact ? 'Single' : '$trackCount titres',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );

    return compact ? SizedBox(width: 120, child: card) : card;
  }
}

// CARTE ALBUM DECOUVERT (GRISE)
class _DiscoveredAlbumCard extends StatelessWidget {
  final DiscoveredAlbum album;
  final AppState state;
  final String artistName;
  final bool compact;

  const _DiscoveredAlbumCard({
    required this.album,
    required this.state,
    required this.artistName,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final coverSide = compact ? 120.0 : 150.0;
    final coverBox = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        image: album.coverUrl != null
            ? DecorationImage(
                image: coverImageProvider(context,
                    path: album.coverUrl!, width: coverSide, height: coverSide),
                fit: BoxFit.cover,
                onError: (_, __) {},
              )
            : null,
      ),
      child: album.coverUrl == null
          ? const Center(
              child: Icon(Icons.album, color: Colors.white54, size: 48))
          : null,
    );
    final cover = compact
        ? SizedBox(width: 120, height: 120, child: coverBox)
        : Expanded(child: coverBox);

    final card = GestureDetector(
      onTap: () => state.pushOverlay(
          DiscoveredAlbumScreen(album: album, filterArtist: artistName)),
      child: Opacity(
        opacity: 0.45,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            cover,
            const SizedBox(height: 8),
            Text(
              album.title,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              compact ? 'Single' : (album.releaseDate ?? ''),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
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

    return compact ? SizedBox(width: 120, child: card) : card;
  }
}

// WIDGETS REUTILISABLES

class _ArtistAvatar extends StatelessWidget {
  final String? url;
  const _ArtistAvatar({this.url});

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;

    if (imageUrl != null) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          image: DecorationImage(
            image: coverImageProvider(context,
                path: imageUrl, width: 80, height: 80),
            fit: BoxFit.cover,
            onError: (_, __) {},
          ),
        ),
      );
    }
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF3E3E3E),
        borderRadius: BorderRadius.circular(40),
      ),
      child: const Icon(Icons.person, color: Colors.white54, size: 40),
    );
  }
}

class _AlbumCover extends StatelessWidget {
  final String? coverPath;
  const _AlbumCover({this.coverPath});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;

    final exists = path != null && path.startsWith('http')
        ? true
        : context.read<AppState>().coverExists(path);

    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
          image: exists && path != null
              ? DecorationImage(
                  image: coverImageProvider(context,
                      path: path,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight),
                  fit: BoxFit.cover,
                  onError: (_, __) {},
                )
              : null,
        ),
        child: exists != true
            ? const Center(
                child: Icon(Icons.album, color: Colors.white54, size: 48),
              )
            : null,
      );
    });
  }
}

class _SkeletonPopularTile extends StatelessWidget {
  final int index;
  const _SkeletonPopularTile({required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${index + 1}',
              style: const TextStyle(color: Colors.white24, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 120,
                  height: 12,
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
