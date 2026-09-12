import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/friend_profile.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/recent_play.dart';
import '../services/navidrome_service.dart';
import '../widgets/smooth_scroll.dart';
import '../widgets/user_avatar.dart';
import 'desktop_track_row.dart';
import 'glass.dart';

/// Profil d'un ami desktop : equivalent de FriendProfileScreen (mobile).
/// Lecture seule (aucune modification possible sur le contenu d'un ami
/// depuis cet ecran), meme donnees (likes, ecoute recente, playlists
/// partagees) que la version mobile.
class DesktopFriendProfileView extends StatefulWidget {
  final FriendProfile friend;
  final VoidCallback onBack;

  const DesktopFriendProfileView({
    super.key,
    required this.friend,
    required this.onBack,
  });

  @override
  State<DesktopFriendProfileView> createState() =>
      _DesktopFriendProfileViewState();
}

class _DesktopFriendProfileViewState extends State<DesktopFriendProfileView> {
  final _scrollController = SmoothScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<List<Track>> _resolvePlaylistTracks(
      AppState state, Playlist playlist) async {
    final byId = {for (final t in state.allTracks) t.id: t};
    if (playlist.trackIds.isNotEmpty) {
      return playlist.trackIds
          .map((id) => byId[id])
          .whereType<Track>()
          .toList();
    }
    final trackIds =
        await NavidromeService().fetchPlaylistSongIds(playlist.serverId!);
    return trackIds.map((id) => byId[id]).whereType<Track>().toList();
  }

  @override
  Widget build(BuildContext context) {
    final friend = widget.friend;
    return Selector<AppState, List<Track>>(
      selector: (_, state) => state.allTracks,
      builder: (context, allTracks, __) {
        final state = context.read<AppState>();
        final byId = {for (final t in allTracks) t.id: t};
        final likedTracks = (friend.likesPlaylist?.trackIds ?? [])
            .map((id) => byId[id])
            .whereType<Track>()
            .toList();
        final recentTracks = (friend.recentPlaysPlaylist?.trackIds ?? [])
            .map((id) => byId[id])
            .whereType<Track>()
            .toList();
        final nowPlayingTrack = friend.nowPlayingTrackId == null
            ? null
            : byId[friend.nowPlayingTrackId];

        void recordRecent() {
          state.recordRecentPlay(RecentPlay(
            type: RecentPlayType.artist,
            id: 'friend_${friend.username}',
            title: friend.username,
            subtitle: 'Ami',
            playedAt: DateTime.now(),
          ));
        }

        // top: DesktopGlass.topInset -- meme raison que les autres vues.
        return Padding(
          padding: const EdgeInsets.only(top: DesktopGlass.topInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GlassIconButton(
                      icon: Icons.arrow_back_rounded, onPressed: widget.onBack),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: _Header(
                        friend: friend,
                        likedCount: likedTracks.length,
                        nowPlayingTrack: nowPlayingTrack,
                        onPlay: likedTracks.isEmpty
                            ? null
                            : () {
                                recordRecent();
                                state.playTrack(likedTracks.first,
                                    trackList: likedTracks);
                              },
                        onShuffle: likedTracks.isEmpty
                            ? null
                            : () {
                                recordRecent();
                                final shuffled = List.of(likedTracks)
                                  ..shuffle();
                                state.playTrack(shuffled.first,
                                    trackList: shuffled);
                              },
                      ),
                    ),
                    if (recentTracks.isNotEmpty) ...[
                      const _SectionTitle('Ecoute recemment'),
                      _trackList(
                        recentTracks,
                        onTap: (t) {
                          recordRecent();
                          state.playTrack(t, trackList: recentTracks);
                        },
                        state: state,
                      ),
                    ],
                    if (likedTracks.isNotEmpty) ...[
                      const _SectionTitle('Titres likes'),
                      _trackList(
                        likedTracks,
                        onTap: (t) {
                          recordRecent();
                          state.playTrack(t, trackList: likedTracks);
                        },
                        state: state,
                      ),
                    ],
                    if (friend.playlists.isNotEmpty) ...[
                      const _SectionTitle('Playlists partagees'),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final pl = friend.playlists[index];
                              return _PlaylistRow(
                                playlist: pl,
                                onTap: () async {
                                  final tracks =
                                      await _resolvePlaylistTracks(state, pl);
                                  if (!context.mounted || tracks.isEmpty) {
                                    return;
                                  }
                                  recordRecent();
                                  state.playTrack(tracks.first,
                                      trackList: tracks);
                                },
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

  Widget _trackList(
    List<Track> tracks, {
    required void Function(Track) onTap,
    required AppState state,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final track = tracks[index];
            return Selector<AppState, Track?>(
              selector: (_, s) => s.currentTrack,
              builder: (context, currentTrack, __) => DesktopTrackRow(
                track: track,
                isPlaying: currentTrack?.id == track.id,
                onTap: () => onTap(track),
                onLike: () => state.toggleLike(track.id),
                onMore: () {},
              ),
            );
          },
          childCount: tracks.length,
        ),
      ),
    );
  }
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
  final FriendProfile friend;
  final int likedCount;
  final Track? nowPlayingTrack;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  const _Header({
    required this.friend,
    required this.likedCount,
    required this.nowPlayingTrack,
    required this.onPlay,
    required this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          UserAvatar(username: friend.username, size: 96),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.username,
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
                  nowPlayingTrack != null
                      ? '🎧 ${nowPlayingTrack!.title} · ${nowPlayingTrack!.artist}'
                      : '$likedCount titre${likedCount > 1 ? 's' : ''} likes · '
                          '${friend.playlists.length} playlist${friend.playlists.length > 1 ? 's' : ''}',
                  style: TextStyle(
                    color: nowPlayingTrack != null
                        ? DesktopGlass.accent
                        : Colors.white54,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                    if (friend.jamSessionId != null) ...[
                      const SizedBox(width: 12),
                      Material(
                        color: DesktopGlass.accent,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => context
                              .read<AppState>()
                              .joinJamSession(friend.jamSessionId!),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.groups,
                                    color: Colors.white, size: 18),
                                SizedBox(width: 6),
                                Text('Rejoindre le Jam',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ),
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

class _PlaylistRow extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  const _PlaylistRow({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DesktopHoverable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.queue_music,
                  color: Colors.white54, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(playlist.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}
