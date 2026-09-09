import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/friend_profile.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/recent_play.dart';
import '../services/navidrome_service.dart';
import '../widgets/track_tile.dart';
import 'playlist_screen.dart';

/// Profil d'un ami : titres likes en premier (comme une page d'artiste),
/// puis ses autres playlists publiques. Lecture seule : aucune modification
/// possible sur le contenu d'un ami depuis cet ecran.
class FriendProfileScreen extends StatefulWidget {
  final FriendProfile friend;
  const FriendProfileScreen({super.key, required this.friend});

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  bool _loadingPlaylistId = false;

  Future<void> _openPlaylist(Playlist playlist) async {
    final state = context.read<AppState>();
    if (playlist.trackIds.isNotEmpty || _loadingPlaylistId) {
      state.pushOverlay(PlaylistScreen(playlist: playlist, readOnly: true));
      return;
    }
    setState(() => _loadingPlaylistId = true);
    final trackIds = await NavidromeService().fetchPlaylistSongIds(playlist.serverId!);
    setState(() => _loadingPlaylistId = false);
    if (!mounted) return;
    final refreshed = Playlist(
      id: playlist.id,
      name: playlist.name,
      trackIds: trackIds,
      serverId: playlist.serverId,
      isPublic: true,
      ownerUsername: playlist.ownerUsername,
      isLikesMirror: playlist.isLikesMirror,
    );
    state.pushOverlay(PlaylistScreen(playlist: refreshed, readOnly: true));
  }

  @override
  Widget build(BuildContext context) {
    final friend = widget.friend;
    return Selector<AppState, List<Track>>(
      selector: (_, state) => state.allTracks,
      builder: (context, allTracks, child) {
        final state = context.read<AppState>();
        final byId = {for (final t in allTracks) t.id: t};
        final likedTracks = (friend.likesPlaylist?.trackIds ?? [])
            .map((id) => byId[id])
            .whereType<Track>()
            .toList();
        final preview = likedTracks.take(5).toList();

        void recordRecent() {
          state.recordRecentPlay(RecentPlay(
            type: RecentPlayType.artist,
            id: 'friend_${friend.username}',
            title: friend.username,
            subtitle: 'Ami',
            playedAt: DateTime.now(),
          ));
        }

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => state.popOverlay(),
            ),
            title: Text(friend.username,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _FriendAvatar(username: friend.username),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              friend.username,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${likedTracks.length} titre${likedTracks.length > 1 ? 's' : ''} likes · ${friend.playlists.length} playlist${friend.playlists.length > 1 ? 's' : ''}',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (likedTracks.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            recordRecent();
                            state.playTrack(likedTracks.first,
                                trackList: likedTracks);
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
                            recordRecent();
                            final shuffled = List.of(likedTracks)..shuffle();
                            state.playTrack(shuffled.first,
                                trackList: shuffled);
                          },
                        ),
                      ],
                    ),
                  ),
                ),

              if (preview.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Titres likes',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (likedTracks.length > preview.length)
                          TextButton(
                            onPressed: () => _openPlaylist(friend.likesPlaylist!),
                            child: const Text('Voir tout',
                                style: TextStyle(color: Color(0xFF1DB954))),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => TrackTile(
                        track: preview[index],
                        onTap: () {
                          recordRecent();
                          state.playTrack(preview[index], trackList: likedTracks);
                        },
                        onLike: () => state.toggleLike(preview[index].id),
                      ),
                      childCount: preview.length,
                    ),
                  ),
                ),
              ],

              if (friend.playlists.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Text(
                      'Playlists partagees',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final playlist = friend.playlists[index];
                        return _FriendPlaylistTile(
                          playlist: playlist,
                          onTap: () => _openPlaylist(playlist),
                        );
                      },
                      childCount: friend.playlists.length,
                    ),
                  ),
                ),
              ],

              if (likedTracks.isEmpty && friend.playlists.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('Rien de partage pour le moment',
                          style: TextStyle(color: Colors.white38)),
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
}

class _FriendPlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  const _FriendPlaylistTile({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.queue_music, color: Colors.white54, size: 24),
      ),
      title: Text(playlist.name,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text('${playlist.trackIds.length} titre(s)',
          style: const TextStyle(color: Colors.white54, fontSize: 13)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  final String username;
  const _FriendAvatar({required this.username});

  static const _colors = [
    Color(0xFF1DB954),
    Color(0xFFE91E63),
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFF9C27B0),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _colors[username.hashCode.abs() % _colors.length];
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(40)),
      child: Center(
        child: Text(initial,
            style: const TextStyle(
                color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
