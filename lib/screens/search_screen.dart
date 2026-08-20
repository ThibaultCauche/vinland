import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/discovered_artist.dart';
import '../models/discovered_album.dart';
import '../models/track.dart';
import '../services/discovery_service.dart';
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
  late TabController _tabController;

  bool _isLoading = false;
  String _query = '';

  List<Track> _localTracks = [];
  List<DiscoveredArtist> _artists = [];
  List<DiscoveredAlbum> _albums = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _query = query;
    });

    final state = context.read<AppState>();

    // Recherche locale + Deezer en parallèle
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
            // ── APP BAR AVEC SEARCH ──
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
                        onChanged: (v) {
                          if (v.isEmpty) {
                            setState(() {
                              _query = '';
                              _localTracks = [];
                              _artists = [];
                              _albums = [];
                            });
                          }
                        },
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
                                    setState(() {
                                      _query = '';
                                      _localTracks = [];
                                      _artists = [];
                                      _albums = [];
                                    });
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

            // ── ONGLETS ──
            if (_query.isNotEmpty) ...[
              TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                indicatorColor: const Color(0xFF1DB954),
                tabs: [
                  Tab(text: 'Titres (${_localTracks.length})'),
                  Tab(text: 'Artistes (${_artists.length})'),
                  Tab(text: 'Albums (${_albums.length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLocalTracks(),
                    _buildArtists(),
                    _buildAlbums(),
                  ],
                ),
              ),
            ] else ...[
              // ── ÉCRAN VIDE AVANT RECHERCHE ──
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

  // ── ONGLET TITRES LOCAUX ──
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
      itemBuilder: (context, i) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF3E3E3E),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(Icons.music_note, color: Colors.white54),
        ),
        title: Text(
          _localTracks[i].title,
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${_localTracks[i].artist} • ${_localTracks[i].album}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        onTap: () => state.playTrack(_localTracks[i]),
      ),
    );
  }

  // ── ONGLET ARTISTES DEEZER ──
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
            final state = context.read<AppState>();
            state.pushOverlay(ArtistScreen(artistName: artist.name));
          },
        );
      },
    );
  }

  // ── ONGLET ALBUMS DEEZER ──
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
            final state = context.read<AppState>();
            state.pushOverlay(DiscoveredAlbumScreen(album: album));
          },
        );
      },
    );
  }
}

// ── WIDGET CARTE ALBUM ──
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
