import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/friend_profile.dart';
import '../models/track.dart';
import '../services/share_inbox_service.dart';
import '../widgets/user_avatar.dart';
import 'friend_profile_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AppState>().loadFriends();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Amis',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => state.loadFriends(),
              ),
            ],
          ),
          body: state.loadingFriends
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF1DB954)),
                )
              : state.friends.isEmpty && state.pendingShares.isEmpty
                  ? _EmptyState(onRetry: () => state.loadFriends())
                  : RefreshIndicator(
                      color: const Color(0xFF1DB954),
                      onRefresh: () => state.loadFriends(),
                      child: ListView(
                        padding: const EdgeInsets.only(top: 8, bottom: 100),
                        children: [
                          if (state.pendingShares.isNotEmpty) ...[
                            const Padding(
                              padding:
                                  EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Text('Partages recus',
                                  style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ),
                            for (final share in state.pendingShares)
                              _ReceivedShareTile(share: share),
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              child: Divider(color: Color(0xFF2A2A2A)),
                            ),
                          ],
                          for (final friend in state.friends)
                            _FriendTile(
                              friend: friend,
                              onTap: () => state.pushOverlay(
                                  FriendProfileScreen(friend: friend)),
                            ),
                        ],
                      ),
                    ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, color: Colors.white24, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Aucun ami pour le moment',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Tout autre compte cree sur ce serveur apparait ici automatiquement, '
              "des qu'il partage au moins une playlist ou ses titres likes.",
              style: TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: const Text('Reessayer',
                  style: TextStyle(color: Color(0xFF1DB954))),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceivedShareTile extends StatelessWidget {
  final ReceivedShare share;
  const _ReceivedShareTile({required this.share});

  IconData get _icon => switch (share.type) {
        'album' => Icons.album_outlined,
        'playlist' => Icons.queue_music,
        _ => Icons.music_note,
      };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF2A2A2A),
        child: Icon(_icon, color: Colors.white70, size: 20),
      ),
      title: Text(share.title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(
        share.subtitle.isEmpty
            ? 'Envoye par ${share.from}'
            : '${share.from} • ${share.subtitle}',
        style: const TextStyle(color: Colors.white54, fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () async {
        final state = context.read<AppState>();
        final ok = await state.openSharedItem(type: share.type, id: share.itemId);
        if (ok) await state.dismissShare(share);
      },
      trailing: IconButton(
        icon: const Icon(Icons.close, color: Colors.white38, size: 20),
        onPressed: () => context.read<AppState>().dismissShare(share),
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  final FriendProfile friend;
  final VoidCallback onTap;
  const _FriendTile({required this.friend, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final likedCount = friend.likesPlaylist?.trackIds.length ?? 0;
    final parts = <String>[];
    if (likedCount > 0)
      parts.add(
          '$likedCount titre${likedCount > 1 ? 's' : ''} lik${likedCount > 1 ? 'es' : 'e'}');
    if (friend.playlists.isNotEmpty) {
      parts.add(
          '${friend.playlists.length} playlist${friend.playlists.length > 1 ? 's' : ''}');
    }

    Track? findNowPlaying(AppState state) {
      if (friend.nowPlayingTrackId == null) return null;
      for (final t in state.allTracks) {
        if (t.id == friend.nowPlayingTrackId) return t;
      }
      return null;
    }

    return Selector<AppState, Track?>(
      selector: (_, state) => findNowPlaying(state),
      builder: (context, nowPlayingTrack, __) {
        final inJam = friend.jamSessionId != null;
        return ListTile(
          onTap: onTap,
          leading: UserAvatar(username: friend.username, size: 44),
          title: Text(friend.username,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w500)),
          subtitle: nowPlayingTrack != null
              ? Text(
                  '🎧 ${nowPlayingTrack.title} · ${nowPlayingTrack.artist}',
                  style:
                      const TextStyle(color: Color(0xFF1DB954), fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : Text(
                  parts.isEmpty
                      ? 'Rien de partage pour le moment'
                      : parts.join(' · '),
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
          trailing: inJam
              ? TextButton.icon(
                  onPressed: () => context
                      .read<AppState>()
                      .joinJamSession(friend.jamSessionId!),
                  icon: const Icon(Icons.groups, size: 16),
                  label: const Text('Rejoindre'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1DB954),
                  ),
                )
              : const Icon(Icons.chevron_right, color: Colors.white38),
        );
      },
    );
  }
}
