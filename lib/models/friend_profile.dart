import 'playlist.dart';

/// Profil d'un autre utilisateur du serveur Navidrome, reconstruit a partir
/// de ses playlists publiques (pas de vrai systeme "ami" cote serveur : tout
/// compte existant est considere comme un ami, voir MusicService.fetchFriends).
class FriendProfile {
  final String username;
  final Playlist? likesPlaylist;
  final Playlist? recentPlaysPlaylist;
  final List<Playlist> playlists;

  /// Id du titre actuellement charge par cet ami (voir MusicService.
  /// updateNowPlaying), null s'il ne partage rien en ce moment ou a
  /// desactive le partage.
  final String? nowPlayingTrackId;

  /// Non-null si cet ami heberge une session Jam en ce moment : permet de
  /// la rejoindre directement (voir AppState.joinJamSession) sans code a
  /// copier-coller.
  final String? jamSessionId;

  FriendProfile({
    required this.username,
    this.likesPlaylist,
    this.recentPlaysPlaylist,
    this.playlists = const [],
    this.nowPlayingTrackId,
    this.jamSessionId,
  });
}
