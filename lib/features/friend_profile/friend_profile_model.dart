import '../../models/friend_profile.dart';
import '../../models/playlist.dart';
import '../../models/recent_play.dart';
import '../../models/track.dart';
import '../shared/library_port.dart';

/// Profil d'un ami (FriendProfileScreen mobile et DesktopFriendProfileView) :
/// ses titres likes et ecoutes recemment retrouves dans notre bibliotheque,
/// ses playlists partagees. Pas de chargement propre, donc pas de
/// ScreenModel : la vue se redessine deja quand la bibliotheque change.
class FriendProfileModel {
  FriendProfileModel({
    required this.friend,
    required this.library,
    required Future<List<String>> Function(String serverId) fetchPlaylistIds,
  }) : _fetchPlaylistIds = fetchPlaylistIds;

  final FriendProfile friend;
  final LibraryPort library;
  final Future<List<String>> Function(String serverId) _fetchPlaylistIds;

  /// Titres d'une playlist de l'ami que l'on a aussi sur le NAS.
  List<Track> _resolve(Playlist? playlist) {
    final ids = playlist?.trackIds ?? const <String>[];
    if (ids.isEmpty) return const [];
    final byId = {for (final t in library.allTracks) t.id: t};
    return ids.map((id) => byId[id]).whereType<Track>().toList();
  }

  List<Track> get likedTracks => _resolve(friend.likesPlaylist);
  List<Track> get recentTracks => _resolve(friend.recentPlaysPlaylist);

  /// Titre que l'ami ecoute en ce moment, s'il est aussi sur notre NAS.
  Track? get nowPlayingTrack {
    final id = friend.nowPlayingTrackId;
    if (id == null) return null;
    for (final t in library.allTracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _recordRecent() {
    library.recordRecentPlay(RecentPlay(
      type: RecentPlayType.friend,
      id: friend.username,
      title: friend.username,
      subtitle: 'Ami',
      playedAt: DateTime.now(),
    ));
  }

  /// Lit [track] dans le contexte de [list] (likes ou ecoutes recentes).
  void play(Track track, List<Track> list) {
    _recordRecent();
    library.playTrack(track, trackList: list);
  }

  /// Lit les likes de l'ami, dans l'ordre ou melanges.
  void playLikes({bool shuffle = false}) {
    final liked = likedTracks;
    if (liked.isEmpty) return;
    final list = shuffle ? (List.of(liked)..shuffle()) : liked;
    play(list.first, list);
  }

  /// Playlist a ouvrir en lecture seule (PlaylistScreen.readOnly) : la
  /// liste des amis ne charge que l'entete des playlists, on recupere ses
  /// titres au moment de l'ouvrir.
  Future<Playlist> playlistToOpen(Playlist playlist) async {
    if (playlist.trackIds.isNotEmpty || playlist.serverId == null) {
      return playlist;
    }
    final trackIds = await _fetchPlaylistIds(playlist.serverId!);
    return Playlist(
      id: playlist.id,
      name: playlist.name,
      trackIds: trackIds,
      serverId: playlist.serverId,
      isPublic: true,
      ownerUsername: playlist.ownerUsername,
      isLikesMirror: playlist.isLikesMirror,
    );
  }
}
