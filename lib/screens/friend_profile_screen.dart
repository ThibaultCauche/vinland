import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/friend_profile.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/recent_play.dart';
import '../services/navidrome_service.dart';
import '../widgets/track_tile.dart';
import '../widgets/user_avatar.dart';
import '../widgets/bottom_bar_reserve.dart';
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
    final trackIds =
        await NavidromeService().fetchPlaylistSongIds(playlist.serverId!);
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
    return Selector<AppState, (List<Track>, bool, String?)>(
      selector: (_, state) =>
          (state.allTracks, state.isJamActive, state.jamSessionId),
      builder: (context, data, child) {
        final (allTracks, isJamActive, currentJamSessionId) = data;
        final state = context.read<AppState>();
        final alreadyInThisJam = friend.jamSessionId != null &&
            isJamActive &&
            currentJamSessionId == friend.jamSessionId;
        final byId = {for (final t in allTracks) t.id: t};
        final likedTracks = (friend.likesPlaylist?.trackIds ?? [])
            .map((id) => byId[id])
            .whereType<Track>()
            .toList();
        final preview = likedTracks.take(5).toList();
        final recentTracks = (friend.recentPlaysPlaylist?.trackIds ?? [])
            .map((id) => byId[id])
            .whereType<Track>()
            .toList();
        final recentPreview = recentTracks.take(5).toList();

        void recordRecent() {
          state.recordRecentPlay(RecentPlay(
            type: RecentPlayType.friend,
            id: friend.username,
            title: friend.username,
            subtitle: 'Ami',
            playedAt: DateTime.now(),
          ));
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
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
                      UserAvatar(username: friend.username, size: 80),
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
                            Builder(builder: (context) {
                              final nowPlayingTrack =
                                  friend.nowPlayingTrackId == null
                                      ? null
                                      : byId[friend.nowPlayingTrackId];
                              if (nowPlayingTrack != null) {
                                return Text(
                                  '🎧 ${nowPlayingTrack.title} · ${nowPlayingTrack.artist}',
                                  style: const TextStyle(
                                      color: Color(0xFF1DB954), fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                );
                              }
                              return Text(
                                '${likedTracks.length} titre${likedTracks.length > 1 ? 's' : ''} likes · ${friend.playlists.length} playlist${friend.playlists.length > 1 ? 's' : ''}',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 14),
                              );
                            }),
                            if (friend.jamSessionId != null) ...[
                              const SizedBox(height: 10),
                              alreadyInThisJam
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.white10,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.groups,
                                              size: 18, color: Colors.white38),
                                          SizedBox(width: 8),
                                          Text('En cours',
                                              style: TextStyle(
                                                  color: Colors.white38)),
                                        ],
                                      ),
                                    )
                                  : ElevatedButton.icon(
                                      onPressed: () async {
                                        final messenger =
                                            ScaffoldMessenger.of(context);
                                        final ok = await state.joinJamSession(
                                            friend.jamSessionId!);
                                        if (!ok) {
                                          messenger.showSnackBar(SnackBar(
                                            content: Text(
                                                '${friend.username} n\'écoute plus -- session introuvable'),
                                            backgroundColor: Colors.red,
                                          ));
                                        }
                                      },
                                      icon: const Icon(Icons.groups, size: 18),
                                      label: const Text('Rejoindre le Jam'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF1DB954),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                      ),
                                    ),
                            ],
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
                            onPressed: () =>
                                _openPlaylist(friend.likesPlaylist!),
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
                      (context, index) => Selector<AppState, Track?>(
                        selector: (_, s) => s.currentTrack,
                        builder: (context, currentTrack, __) => TrackTile(
                          track: preview[index],
                          isPlaying: currentTrack?.id == preview[index].id,
                          onTap: () {
                            recordRecent();
                            state.playTrack(preview[index],
                                trackList: likedTracks);
                          },
                          onLike: () => state.toggleLike(preview[index].id),
                        ),
                      ),
                      childCount: preview.length,
                    ),
                  ),
                ),
              ],
              if (recentPreview.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Écouté récemment',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (recentTracks.length > recentPreview.length)
                          TextButton(
                            onPressed: () =>
                                _openPlaylist(friend.recentPlaysPlaylist!),
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
                      (context, index) => Selector<AppState, Track?>(
                        selector: (_, s) => s.currentTrack,
                        builder: (context, currentTrack, __) => TrackTile(
                          track: recentPreview[index],
                          isPlaying:
                              currentTrack?.id == recentPreview[index].id,
                          onTap: () {
                            recordRecent();
                            state.playTrack(recentPreview[index],
                                trackList: recentTracks);
                          },
                          onLike: () =>
                              state.toggleLike(recentPreview[index].id),
                        ),
                      ),
                      childCount: recentPreview.length,
                    ),
                  ),
                ),
              ],
              if (friend.playlists.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Text(
                      'Playlists partagées',
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
              if (likedTracks.isEmpty &&
                  recentTracks.isEmpty &&
                  friend.playlists.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('Rien de partage pour le moment',
                          style: TextStyle(color: Colors.white38)),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                  child: SizedBox(height: bottomBarReserve(context))),
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
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text('${playlist.trackIds.length} titre(s)',
          style: const TextStyle(color: Colors.white54, fontSize: 13)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
    );
  }
}
