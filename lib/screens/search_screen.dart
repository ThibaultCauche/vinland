import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/discovered_artist.dart';
import '../models/discovered_album.dart';
import '../models/track.dart';
import '../models/search_history_item.dart';
import '../services/discovery_service.dart';
import '../services/search_history_service.dart';
import '../screens/artist_screen.dart';
import '../screens/discovered_album_screen.dart';

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
  late TabController _tabController;

  bool _isLoading = false;
  String _query = '';
  Timer? _debounce;

  List<Track> _localTracks = [];
  List<DiscoveredArtist> _artists = [];
  List<DiscoveredAlbum> _albums = [];
  List<SearchHistoryItem> _history = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        _localTracks = [];
        _artists = [];
        _albums = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(value);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _query = query;
    });

    final state = context.read<AppState>();
    final local = state.musicService.searchTracks(query);
    final artistsFuture = _discovery.searchArtists(query, limit: 10);
    final albumsFuture = _discovery.searchAlbums(query, limit: 15);

    final results = await Future.wait([artistsFuture, albumsFuture]);

    if (mounted) {
      setState(() {
        _localTracks = local;
        _artists = results[0] as List<DiscoveredArtist>;
        _albums = results[1] as List<DiscoveredAlbum>;
        _isLoading = false;
      });
    }
  }

  void _onHistoryTap(SearchHistoryItem item) {
    switch (item.type) {
      case 'artist':
        if (item.name != null) {
          Navigator.pop(context);
          final state = context.read<AppState>();
          state.pushOverlay(ArtistScreen(artistName: item.name!));
        }
        break;
      case 'album':
        if (item.id != null) {
          Navigator.pop(context);
          final state = context.read<AppState>();
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
                image: NetworkImage(item.imageUrl!),
                fit: BoxFit.cover,
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
    final hasResults =
        _localTracks.isNotEmpty || _artists.isNotEmpty || _albums.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
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
                    onPressed: () => Navigator.pop(context),
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
                  Tab(text: 'Titres (${_localTracks.length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildArtists(),
                    _buildAlbums(),
                    _buildLocalTracks(),
                  ],
                ),
              ),
            ] else if (_history.isNotEmpty) ...[
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 8),
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

  Widget _buildLocalTracks() {
    if (_localTracks.isEmpty) {
      return const Center(
        child:
            Text('Aucun titre local', style: TextStyle(color: Colors.white38)),
      );
    }
    final state = context.read<AppState>();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: _localTracks.length,
      itemBuilder: (context, i) {
        final track = _localTracks[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF3E3E3E),
              borderRadius: BorderRadius.circular(4),
              image:
                  track.coverPath != null && track.coverPath!.startsWith('http')
                      ? DecorationImage(
                          image: NetworkImage(track.coverPath!),
                          fit: BoxFit.cover,
                        )
                      : null,
            ),
            child:
                track.coverPath == null || !track.coverPath!.startsWith('http')
                    ? const Icon(Icons.music_note, color: Colors.white54)
                    : null,
          ),
          title: Text(
            track.title,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '${track.artist} • ${track.album}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          onTap: () async {
            await _historyService.addTrack(
              track.title,
              track.id,
              track.artist,
              query: _query,
              imageUrl: track.coverPath?.startsWith('http') == true
                  ? track.coverPath
                  : null,
            );
            state.playTrack(track);
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
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: _artists.length,
      itemBuilder: (context, i) {
        final artist = _artists[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF3E3E3E),
            backgroundImage: artist.pictureUrl != null
                ? NetworkImage(artist.pictureUrl!)
                : null,
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
            Navigator.pop(context);
            final state = context.read<AppState>();
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
            Navigator.pop(context);
            final state = context.read<AppState>();
            state.pushOverlay(DiscoveredAlbumScreen(album: album));
          },
        );
      },
    );
  }
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
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(8),
                  image: coverUrl != null
                      ? DecorationImage(
                          image: NetworkImage(coverUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: coverUrl == null
                    ? const Center(
                        child:
                            Icon(Icons.album, color: Colors.white54, size: 48))
                    : null,
              ),
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
