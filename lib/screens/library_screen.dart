import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../widgets/track_tile.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Text(
                      'Bibliothèque',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.white),
                      onPressed: () => _showCreatePlaylistDialog(context),
                    ),
                  ],
                ),
              ),
              // Tabs
              TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                indicatorColor: Colors.white,
                indicatorWeight: 2,
                tabs: const [
                  Tab(text: 'Titres likés'),
                  Tab(text: 'Albums'),
                  Tab(text: 'Playlists'),
                ],
              ),
              // Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLikedTracks(state),
                    _buildAlbums(state),
                    _buildPlaylists(state),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLikedTracks(AppState state) {
    if (state.likedTracks.isEmpty) {
      return _buildEmpty('Aucun titre liké');
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: state.likedTracks.length,
      itemBuilder: (context, i) => TrackTile(
        track: state.likedTracks[i],
        onTap: () => state.playTrack(state.likedTracks[i]),
        onLike: () => state.toggleLike(state.likedTracks[i].id),
      ),
    );
  }

  Widget _buildAlbums(AppState state) {
    final savedAlbums = state.allTracks
        .fold<Map<String, List>>({}, (map, track) {
          map.putIfAbsent(track.album, () => [track.artist, <String>[]]);
          (map[track.album]![1] as List<String>).add(track.id);
          return map;
        })
        .entries
        .toList();

    if (savedAlbums.isEmpty) {
      return _buildEmpty('Aucun album');
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: savedAlbums.length,
      itemBuilder: (context, i) {
        final album = savedAlbums[i];
        return GestureDetector(
          onTap: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(Icons.album, color: Colors.white54, size: 48),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.key,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                album.value[0] as String,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaylists(AppState state) {
    // TODO: récupérer les vraies playlists depuis le service
    return _buildEmpty('Aucune playlist');
  }

  Widget _buildEmpty(String text) {
    return Center(
      child: Text(text, style: const TextStyle(color: Colors.white38)),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Nouvelle playlist',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Nom de la playlist',
            hintStyle: TextStyle(color: Colors.white38),
            border: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2A2A2A))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                context.read<AppState>().createPlaylist(controller.text);
                Navigator.pop(context);
              }
            },
            child:
                const Text('Créer', style: TextStyle(color: Color(0xFF1DB954))),
          ),
        ],
      ),
    );
  }
}
