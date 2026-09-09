import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/friend_profile.dart';
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
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            elevation: 0,
            title: const Text('Amis',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              : state.friends.isEmpty
                  ? _EmptyState(onRetry: () => state.loadFriends())
                  : RefreshIndicator(
                      color: const Color(0xFF1DB954),
                      onRefresh: () => state.loadFriends(),
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 100),
                        itemCount: state.friends.length,
                        itemBuilder: (context, i) {
                          final friend = state.friends[i];
                          return _FriendTile(
                            friend: friend,
                            onTap: () => state
                                .pushOverlay(FriendProfileScreen(friend: friend)),
                          );
                        },
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

class _FriendTile extends StatelessWidget {
  final FriendProfile friend;
  final VoidCallback onTap;
  const _FriendTile({required this.friend, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final likedCount = friend.likesPlaylist?.trackIds.length ?? 0;
    final parts = <String>[];
    if (likedCount > 0) parts.add('$likedCount titre${likedCount > 1 ? 's' : ''} lik${likedCount > 1 ? 'es' : 'e'}');
    if (friend.playlists.isNotEmpty) {
      parts.add(
          '${friend.playlists.length} playlist${friend.playlists.length > 1 ? 's' : ''}');
    }

    return ListTile(
      onTap: onTap,
      leading: _Avatar(username: friend.username),
      title: Text(friend.username,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(
        parts.isEmpty ? 'Rien de partage pour le moment' : parts.join(' · '),
        style: const TextStyle(color: Colors.white54, fontSize: 13),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String username;
  const _Avatar({required this.username});

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
    return CircleAvatar(
      radius: 22,
      backgroundColor: color,
      child: Text(initial,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}
