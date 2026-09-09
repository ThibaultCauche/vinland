import 'playlist.dart';

/// Profil d'un autre utilisateur du serveur Navidrome, reconstruit a partir
/// de ses playlists publiques (pas de vrai systeme "ami" cote serveur : tout
/// compte existant est considere comme un ami, voir MusicService.fetchFriends).
class FriendProfile {
  final String username;
  final Playlist? likesPlaylist;
  final List<Playlist> playlists;

  FriendProfile({
    required this.username,
    this.likesPlaylist,
    this.playlists = const [],
  });
}
