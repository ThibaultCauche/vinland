import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/discovered_artist.dart';
import '../models/discovered_album.dart';
import '../models/discovered_track.dart';
import '../models/track.dart';
import '../models/search_history_item.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../services/matching_service.dart';
import '../services/search_history_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/download_button.dart';
import '../widgets/download_progress_dialog.dart';
import '../screens/artist_screen.dart';
import '../screens/album_screen.dart';
import '../screens/discovered_album_screen.dart';
import '../models/album.dart';
import '../widgets/bottom_bar_reserve.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _discovery = DiscoveryService();
  final _historyService = SearchHistoryService();
  final _downloadWorker = DownloadWorkerService();
  late TabController _tabController;

  bool _isLoading = false;
  String _query = '';
  Timer? _debounce;

  List<_SearchTrack> _tracks = [];
  List<DiscoveredArtist> _artists = [];
  List<DiscoveredAlbum> _albums = [];
  List<SearchHistoryItem> _history = [];
  final Map<int, DownloadUiState> _downloadStates = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final state = context.read<AppState>();
    _historyService.setCurrentUser(state.currentUserId);
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    _tabController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    await _historyService.ensureLoaded();
    if (mounted) setState(() => _history = _historyService.history);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _query = '';
        _tracks = [];
        _artists = [];
        _albums = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(value);
    });
  }

  Track? _findLocalTrack(DiscoveredTrack dt, List<Track> candidates) {
    for (final t in candidates) {
      if (MatchingService.artistsMatch(t.artist, dt.artistName) &&
          MatchingService.titlesMatch(t.title, dt.title)) {
        return t;
      }
    }
    return null;
  }

  // Recherche Deezer (pas uniquement les titres deja sur le NAS, voir
  // DesktopSearchView pour la meme logique cote desktop) : avant, l'onglet
  // "Titres" ne cherchait QUE dans la bibliotheque locale deja synchronisee,
  // donc un titre pas encore telecharge n'y apparaissait jamais meme en le
  // tapant exactement -- il fallait passer par Artiste puis Album pour le
  // retrouver et le telecharger (retour utilisateur).
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _query = query;
    });

    final state = context.read<AppState>();
    final results = await Future.wait([
      _discovery.searchArtists(query, limit: 10),
      _discovery.searchAlbums(query, limit: 15),
      _discovery.searchTracks(query, limit: 15),
    ]);

    if (mounted) {
      final localTracks = state.allTracks;
      final discoveredTracks = results[2] as List<DiscoveredTrack>;
      setState(() {
        _tracks = [
          for (final dt in discoveredTracks)
            _SearchTrack(discovered: dt, local: _findLocalTrack(dt, localTracks)),
        ];
        _artists = results[0] as List<DiscoveredArtist>;
        _albums = results[1] as List<DiscoveredAlbum>;
        _isLoading = false;
      });
    }
  }

  /// Meme logique que DesktopSearchView._downloadTrack -- jusqu'ici jamais
  /// branchee cote mobile, l'onglet "Titres" ne montrant que des titres deja
  /// locaux.
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

    if (!mounted) return;
    final status = await showDownloadProgressDialog(context,
        worker: _downloadWorker, jobId: jobId);
    if (!mounted) return;

    if (status.state == DownloadJobState.done) {
      await context
          .read<AppState>()
          .handleTrackDownloaded(track.artistName, track.title);
      if (mounted) {
        setState(() {
          _downloadStates.remove(track.id);
          final i = _tracks.indexWhere((t) => t.discovered.id == track.id);
          if (i != -1) {
            _tracks[i] = _SearchTrack(
              discovered: track,
              local: _findLocalTrack(track, context.read<AppState>().allTracks),
            );
          }
        });
      }
    } else {
      setState(() => _downloadStates[track.id] = DownloadUiState.failed);
    }
  }

  void _onHistoryTap(SearchHistoryItem item) {
    switch (item.type) {
      case 'artist':
        if (item.name != null) {
          final state = context.read<AppState>();
          state.popOverlay();
          state.pushOverlay(ArtistScreen(artistName: item.name!));
        }
        break;
      case 'album':
        if (item.id != null) {
          final state = context.read<AppState>();
          state.popOverlay();
          state.pushOverlay(
              DiscoveredAlbumScreen.fromAlbumId(int.parse(item.id!)));
        }
        break;
      case 'track':
        if (item.id != null) {
          final state = context.read<AppState>();
          final matches =
              state.allTracks.where((t) => t.id == item.id).toList();
          if (matches.isNotEmpty) {
            FocusScope.of(context).unfocus();
            state.popOverlay();
            state.playTrack(matches.first);
          }
        }
        break;
    }
  }

  Widget _historyLeading(SearchHistoryItem item) {
    final isArtist = item.type == 'artist';
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF3E3E3E),
        borderRadius: BorderRadius.circular(isArtist ? 24 : 4),
        image: item.imageUrl != null
            ? DecorationImage(
                image: coverImageProvider(context,
                    path: item.imageUrl!, width: 48, height: 48),
                fit: BoxFit.cover,
                onError: (_, __) {},
              )
            : null,
      ),
      child: item.imageUrl == null
          ? Icon(
              isArtist
                  ? Icons.person
                  : item.type == 'album'
                      ? Icons.album
                      : Icons.music_note,
              color: Colors.white54,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => context.read<AppState>().popOverlay(),
                  ),
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        onSubmitted: _performSearch,
                        onChanged: _onSearchChanged,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Titres, artistes, albums...',
                          hintStyle: const TextStyle(
                              color: Colors.white38, fontSize: 14),
                          prefixIcon: const Icon(Icons.search,
                              color: Colors.white54, size: 20),
                          suffixIcon: _controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear,
                                      color: Colors.white54, size: 18),
                                  onPressed: () {
                                    _controller.clear();
                                    _onSearchChanged('');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const LinearProgressIndicator(
                color: Color(0xFF1DB954),
                backgroundColor: Colors.transparent,
              ),
            if (_query.isNotEmpty) ...[
              TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                indicatorColor: const Color(0xFF1DB954),
                tabs: [
                  Tab(text: 'Artistes (${_artists.length})'),
                  Tab(text: 'Albums (${_albums.length})'),
                  Tab(text: 'Titres (${_tracks.length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildArtists(),
                    _buildAlbums(),
                    _buildTracks(),
                  ],
                ),
              ),
            ] else if (_history.isNotEmpty) ...[
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.only(
                      top: 8, bottom: bottomBarReserve(context)),
                  itemCount: _history.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Récemment consultés',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                await _historyService.clear();
                                setState(() => _history = []);
                              },
                              child: const Text('Effacer',
                                  style: TextStyle(color: Color(0xFF1DB954))),
                            ),
                          ],
                        ),
                      );
                    }
                    final item = _history[index - 1];
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      leading: _historyLeading(item),
                      title: Text(
                        item.displayName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                      ),
                      subtitle: item.subtitle != null
                          ? Text(
                              item.subtitle!,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12),
                            )
                          : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white38, size: 18),
                        onPressed: () async {
                          await _historyService.remove(item);
                          setState(() => _history = _historyService.history);
                        },
                      ),
                      onTap: () => _onHistoryTap(item),
                    );
                  },
                ),
              ),
            ] else ...[
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, color: Colors.white24, size: 64),
                      SizedBox(height: 16),
                      Text(
                        'Recherchez un artiste, un album ou un titre',
                        style: TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTracks() {
    if (_tracks.isEmpty) {
      return const Center(
        child: Text('Aucun titre trouvé', style: TextStyle(color: Colors.white38)),
      );
    }
    final state = context.read<AppState>();
    return ListView.builder(
      padding: EdgeInsets.only(bottom: bottomBarReserve(context)),
      itemCount: _tracks.length,
      itemBuilder: (context, i) {
        final t = _tracks[i];
        final discovered = t.discovered;
        final localTrack = t.local;
        final isAvailable = localTrack != null;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF3E3E3E),
              borderRadius: BorderRadius.circular(4),
              image: discovered.coverUrl != null
                  ? DecorationImage(
                      image: coverImageProvider(context,
                          path: discovered.coverUrl!, width: 48, height: 48),
                      fit: BoxFit.cover,
                      onError: (_, __) {},
                    )
                  : null,
            ),
            child: discovered.coverUrl == null
                ? const Icon(Icons.music_note, color: Colors.white54)
                : null,
          ),
          title: Text(
            discovered.title,
            style: TextStyle(
              color: isAvailable ? Colors.white : Colors.white38,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            localTrack != null
                ? '${localTrack.artist} • ${localTrack.album}'
                : discovered.artistName,
            style: TextStyle(
              color: isAvailable ? Colors.white54 : Colors.white24,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isAvailable
              ? IconButton(
                  icon: Icon(
                    localTrack.isLiked ? Icons.favorite : Icons.favorite_border,
                    color: localTrack.isLiked
                        ? const Color(0xFF1DB954)
                        : Colors.white54,
                    size: 18,
                  ),
                  onPressed: () => state.toggleLike(localTrack.id),
                )
              : DownloadStateIcon(
                  state: _downloadStates[discovered.id],
                  showDownloadButton: _downloadWorker.isConfigured,
                  onDownloadTap: () => _downloadTrack(discovered),
                ),
          onTap: !isAvailable
              ? null
              : () async {
                  await _historyService.addTrack(
                    localTrack.title,
                    localTrack.id,
                    localTrack.artist,
                    query: _query,
                    imageUrl: localTrack.coverPath?.startsWith('http') == true
                        ? localTrack.coverPath
                        : null,
                  );
                  if (!mounted) return;
                  FocusScope.of(context).unfocus();
                  state.popOverlay();
                  state.playTrack(localTrack);
                },
        );
      },
    );
  }

  Widget _buildArtists() {
    if (_artists.isEmpty) {
      return const Center(
        child: Text('Aucun artiste trouvé',
            style: TextStyle(color: Colors.white38)),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: bottomBarReserve(context)),
      itemCount: _artists.length,
      itemBuilder: (context, i) {
        final artist = _artists[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF3E3E3E),
            backgroundImage: artist.pictureUrl != null
                ? coverImageProvider(context,
                    path: artist.pictureUrl!, width: 48, height: 48)
                : null,
            onBackgroundImageError:
                artist.pictureUrl != null ? (_, __) {} : null,
            child: artist.pictureUrl == null
                ? const Icon(Icons.person, color: Colors.white54)
                : null,
          ),
          title: Text(
            artist.name,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: artist.nbFans != null
              ? Text('${artist.nbFans} fans',
                  style: const TextStyle(color: Colors.white54, fontSize: 12))
              : null,
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: () {
            _historyService.addArtist(
              artist.name,
              artist.id.toString(),
              query: _query,
              imageUrl: artist.pictureUrl,
            );
            final state = context.read<AppState>();
            state.popOverlay();
            state.pushOverlay(ArtistScreen(artistName: artist.name));
          },
        );
      },
    );
  }

  Widget _buildAlbums() {
    if (_albums.isEmpty) {
      return const Center(
        child:
            Text('Aucun album trouvé', style: TextStyle(color: Colors.white38)),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomBarReserve(context)),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _albums.length,
      itemBuilder: (context, i) {
        final album = _albums[i];
        return _AlbumCard(
          title: album.title,
          artist: album.artistName,
          coverUrl: album.coverUrl,
          isInLibrary: album.isInLibrary,
          onTap: () {
            _historyService.addAlbum(
              album.title,
              album.id.toString(),
              album.artistName,
              query: _query,
              imageUrl: album.coverUrl,
            );
            final state = context.read<AppState>();
            state.popOverlay();
            Album? localAlbum;
            try {
              localAlbum = state.albums.firstWhere(
                (a) =>
                    a.title.toLowerCase().trim() ==
                    album.title.toLowerCase().trim(),
              );
            } catch (_) {
              localAlbum = null;
            }

            if (localAlbum != null) {
              state.pushOverlay(AlbumScreen(album: localAlbum));
            } else {
              state.pushOverlay(DiscoveredAlbumScreen(album: album));
            }
          },
        );
      },
    );
  }
}

/// Un resultat de l'onglet "Titres" : toujours issu de la recherche Deezer
/// (voir _performSearch), avec un lien vers le titre local correspondant
/// quand il existe deja -- meme structure que DesktopSearchView._SearchTrack.
class _SearchTrack {
  final DiscoveredTrack discovered;
  final Track? local;
  const _SearchTrack({required this.discovered, this.local});
}

class _AlbumCard extends StatelessWidget {
  final String title;
  final String artist;
  final String? coverUrl;
  final bool isInLibrary;
  final VoidCallback onTap;

  const _AlbumCard({
    required this.title,
    required this.artist,
    this.coverUrl,
    required this.isInLibrary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isInLibrary ? 0.5 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                    image: coverUrl != null
                        ? DecorationImage(
                            image: coverImageProvider(context,
                                path: coverUrl!,
                                width: constraints.maxWidth,
                                height: constraints.maxHeight),
                            fit: BoxFit.cover,
                            onError: (_, __) {},
                          )
                        : null,
                  ),
                  child: coverUrl == null
                      ? const Center(
                          child: Icon(Icons.album,
                              color: Colors.white54, size: 48))
                      : null,
                );
              }),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              artist,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (isInLibrary)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: Color(0xFF1DB954), size: 12),
                    SizedBox(width: 4),
                    Text('Dans la bibliothèque',
                        style:
                            TextStyle(color: Color(0xFF1DB954), fontSize: 10)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
