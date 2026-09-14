import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/friend_profile.dart';
import '../models/track.dart';
import '../services/share_inbox_service.dart';
import '../widgets/smooth_scroll.dart';
import '../widgets/user_avatar.dart';
import 'glass.dart';

/// Onglet Amis desktop : equivalent de FriendsScreen (mobile). Meme donnees
/// (AppState.friends/loadFriends), juste reskin verre depoli et naviguee via
/// la pile locale de DesktopAppShell plutot que les overlays d'AppState.
class DesktopFriendsView extends StatefulWidget {
  final ValueChanged<FriendProfile> onOpenFriend;
  const DesktopFriendsView({super.key, required this.onOpenFriend});

  @override
  State<DesktopFriendsView> createState() => _DesktopFriendsViewState();
}

class _DesktopFriendsViewState extends State<DesktopFriendsView> {
  final _scrollController = SmoothScrollController();

  @override
  void initState() {
    super.initState();
    context.read<AppState>().loadFriends();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, __) {
        // top: DesktopGlass.topInset -- meme raison que les autres vues.
        return Padding(
          padding: const EdgeInsets.only(top: DesktopGlass.topInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Amis',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  GlassIconButton(
                    icon: Icons.refresh_rounded,
                    onPressed: () => state.loadFriends(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (state.pendingShares.isNotEmpty) ...[
                const Text('Partages recus',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                for (final share in state.pendingShares)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ReceivedShareCard(share: share),
                  ),
                const SizedBox(height: 10),
                Divider(color: Colors.white.withOpacity(0.12), height: 1),
                const SizedBox(height: 20),
              ],
              Expanded(
                child: state.loadingFriends
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: DesktopGlass.accent),
                      )
                    : state.friends.isEmpty
                        ? const _EmptyState()
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.only(
                                bottom: DesktopGlass.playerBarReserve),
                            itemCount: state.friends.length,
                            itemBuilder: (context, i) {
                              final friend = state.friends[i];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _FriendCard(
                                  friend: friend,
                                  onTap: () => widget.onOpenFriend(friend),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, color: Colors.white24, size: 56),
            SizedBox(height: 16),
            Text(
              'Aucun ami pour le moment',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Tout autre compte cree sur ce serveur apparait ici '
              "automatiquement, des qu'il partage au moins une playlist ou "
              'ses titres likes.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceivedShareCard extends StatelessWidget {
  final ReceivedShare share;
  const _ReceivedShareCard({required this.share});

  IconData get _icon => switch (share.type) {
        'album' => Icons.album_outlined,
        'playlist' => Icons.queue_music,
        _ => Icons.music_note,
      };

  @override
  Widget build(BuildContext context) {
    return DesktopHoverable(
      onTap: () async {
        final state = context.read<AppState>();
        final ok = await state.openSharedItem(type: share.type, id: share.itemId);
        if (ok) await state.dismissShare(share);
      },
      borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white.withOpacity(0.08),
              child: Icon(_icon, color: Colors.white70, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(share.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    share.subtitle.isEmpty
                        ? 'Envoye par ${share.from}'
                        : '${share.from} • ${share.subtitle}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            GlassIconButton(
              icon: Icons.close_rounded,
              size: 18,
              onPressed: () => context.read<AppState>().dismissShare(share),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  final FriendProfile friend;
  final VoidCallback onTap;
  const _FriendCard({required this.friend, required this.onTap});

  Track? _findNowPlaying(AppState state) {
    if (friend.nowPlayingTrackId == null) return null;
    for (final t in state.allTracks) {
      if (t.id == friend.nowPlayingTrackId) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final likedCount = friend.likesPlaylist?.trackIds.length ?? 0;
    final parts = <String>[];
    if (likedCount > 0) {
      parts.add(
          '$likedCount titre${likedCount > 1 ? 's' : ''} lik${likedCount > 1 ? 'es' : 'e'}');
    }
    if (friend.playlists.isNotEmpty) {
      parts.add(
          '${friend.playlists.length} playlist${friend.playlists.length > 1 ? 's' : ''}');
    }

    return Selector<AppState, Track?>(
      selector: (_, state) => _findNowPlaying(state),
      builder: (context, nowPlayingTrack, __) {
        final inJam = friend.jamSessionId != null;
        return DesktopHoverable(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                UserAvatar(username: friend.username, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(friend.username,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      nowPlayingTrack != null
                          ? Text(
                              '🎧 ${nowPlayingTrack.title} · ${nowPlayingTrack.artist}',
                              style: const TextStyle(
                                  color: DesktopGlass.accent, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : Text(
                              parts.isEmpty
                                  ? 'Rien de partage pour le moment'
                                  : parts.join(' · '),
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                    ],
                  ),
                ),
                if (inJam)
                  Material(
                    color: DesktopGlass.accent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context
                          .read<AppState>()
                          .joinJamSession(friend.jamSessionId!),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.groups, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text('Rejoindre',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
        );
      },
    );
  }
}
