import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../screens/settings_screen.dart';
import '../screens/missing_tracks_screen.dart';
import '../widgets/search_bar.dart';
import '../widgets/track_tile.dart';
import '../services/music_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState,
        (List<Track>, List<Track>, String?, List<Map<String, dynamic>>)>(
      selector: (_, state) => (
        state.allTracks,
        state.likedTracks,
        state.userName,
        state.missingTracks,
      ),
      builder: (context, data, child) {
        final (allTracks, likedTracks, userName, missingTracks) = data;
        final state = context.read<AppState>();
        return SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => _showProfileMenu(context),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFF3E3E3E),
                          child: Text(
                            userName?.substring(0, 1).toUpperCase() ?? 'U',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: SearchBarWidget(),
                      ),
                    ],
                  ),
                ),
              ),
              _buildSectionTitleWithAction(
                'Toutes les musiques',
                'Voir tout',
                () => _showAllTracks(context),
              ),
              allTracks.isEmpty
                  ? _buildEmpty('Aucune musique trouvée')
                  : SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => TrackTile(
                            track: allTracks[index],
                            onTap: () => state.playTrack(allTracks[index]),
                            onLike: () => state.toggleLike(allTracks[index].id),
                          ),
                          childCount:
                              allTracks.length > 5 ? 5 : allTracks.length,
                        ),
                      ),
                    ),
              _buildSectionTitle('Récemment écouté'),
              _buildRecentlyPlayed(state),
              _buildSectionTitle('Titres likés'),
              likedTracks.isEmpty
                  ? _buildEmpty('Aucun titre liké')
                  : SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => TrackTile(
                            track: likedTracks[index],
                            onTap: () => state.playTrack(likedTracks[index]),
                            onLike: () =>
                                state.toggleLike(likedTracks[index].id),
                          ),
                          childCount: likedTracks.length,
                        ),
                      ),
                    ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitleWithAction(
      String title, String action, VoidCallback onTap) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            GestureDetector(
              onTap: onTap,
              child: Text(
                action,
                style: const TextStyle(
                  color: Color(0xFF1DB954),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAllTracks(BuildContext context) {
    final state = context.read<AppState>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            elevation: 0,
            title: const Text(
              'Toutes les musiques',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: ListView.builder(
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: state.allTracks.length,
            itemBuilder: (context, index) => TrackTile(
              track: state.allTracks[index],
              onTap: () => state.playTrack(state.allTracks[index]),
              onLike: () => state.toggleLike(state.allTracks[index].id),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(String text) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(text, style: const TextStyle(color: Colors.white38)),
        ),
      ),
    );
  }

  Widget _buildRecentlyPlayed(AppState state) {
    final recentAlbums = <String>[];
    final recentTracks = state.allTracks
        .where((t) => t.lastPlayed != null)
        .toList()
      ..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));

    for (final track in recentTracks) {
      if (!recentAlbums.contains(track.album)) {
        recentAlbums.add(track.album);
      }
    }

    if (recentAlbums.isEmpty) {
      return _buildEmpty('Commencez à écouter de la musique');
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 2.8,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final albumTitle = recentAlbums[index];
            final albumTracks =
                state.allTracks.where((t) => t.album == albumTitle).toList();
            final artist =
                albumTracks.isNotEmpty ? albumTracks.first.artist : 'Artiste';
            final coverPath =
                albumTracks.isNotEmpty ? albumTracks.first.coverPath : null;

            return GestureDetector(
              onTap: () {
                if (albumTracks.isNotEmpty) {
                  state.playTrack(albumTracks.first, trackList: albumTracks);
                }
              },
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    _AlbumCover(coverPath: coverPath),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              albumTitle,
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
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: recentAlbums.length,
        ),
      ),
    );
  }

  void _showProfileMenu(BuildContext context) {
    final state = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF3E3E3E),
                  child: Text(
                    state.userName?.substring(0, 1).toUpperCase() ?? 'U',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(
                  state.userName ?? 'Utilisateur',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  state.userEmail ?? '',
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
              const Divider(color: Color(0xFF2A2A2A)),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.white54),
                title: const Text('Paramètres',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  state.pushOverlay(const SettingsScreen());
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.playlist_remove, color: Colors.orange),
                title: const Text('Titres manquants',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  '${state.missingTracks.length} titre(s) à importer',
                  style: const TextStyle(color: Colors.white54),
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (state.missingTracks.isNotEmpty) {
                    state.pushOverlay(const MissingTracksScreen());
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Aucun titre manquant')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.white54),
                title: const Text('Se déconnecter',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  state.logout();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumCover extends StatelessWidget {
  final String? coverPath;
  const _AlbumCover({this.coverPath});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final exists = context.read<MusicService>().coverExists(path);

    if (exists && path != null) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
          image: DecorationImage(
            image: FileImage(File(path)),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        color: Color(0xFF3E3E3E),
        borderRadius: BorderRadius.horizontal(left: Radius.circular(6)),
      ),
      child: const Icon(Icons.album, color: Colors.white54),
    );
  }
}
