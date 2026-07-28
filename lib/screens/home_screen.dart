import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../widgets/search_bar.dart';
import '../widgets/track_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return SafeArea(
          child: CustomScrollView(
            slivers: [
              // Header avec profil
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _showProfileMenu(context),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFF3E3E3E),
                          child: Text(
                            state.userName?.substring(0, 1).toUpperCase() ??
                                'U',
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

              // Toutes les musiques
              _buildSectionTitle('Toutes les musiques'),
              state.allTracks.isEmpty
                  ? _buildEmpty('Aucune musique trouv\u00e9e')
                  : SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => TrackTile(
                            track: state.allTracks[index],
                            onTap: () =>
                                state.playTrack(state.allTracks[index]),
                            onLike: () =>
                                state.toggleLike(state.allTracks[index].id),
                          ),
                          childCount: state.allTracks.length,
                        ),
                      ),
                    ),

              // R\u00e9cemment \u00e9cout\u00e9 (albums et playlists uniquement)
              _buildSectionTitle('R\u00e9cemment \u00e9cout\u00e9'),
              _buildRecentlyPlayed(state),

              // Titres lik\u00e9s
              _buildSectionTitle('Titres lik\u00e9s'),
              state.likedTracks.isEmpty
                  ? _buildEmpty('Aucun titre lik\u00e9')
                  : SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => TrackTile(
                            track: state.likedTracks[index],
                            onTap: () =>
                                state.playTrack(state.likedTracks[index]),
                            onLike: () =>
                                state.toggleLike(state.likedTracks[index].id),
                          ),
                          childCount: state.likedTracks.length,
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
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: Color(0xFF3E3E3E),
                        borderRadius:
                            BorderRadius.horizontal(left: Radius.circular(6)),
                      ),
                      child: const Icon(Icons.album, color: Colors.white54),
                    ),
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
                title: const Text('Param\u00e8tres',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.white54),
                title: const Text('Se d\u00e9connecter',
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
