import '../providers/app_state.dart';
import '../screens/album_screen.dart';
import '../screens/playlist_screen.dart';
import '../widgets/player_screen.dart';

/// Ouvre l'element concerne par un lien vinland:// ou un partage recu en
/// boite de reception -- meme resolution/navigation dans les deux cas (voir
/// DeepLinkService). Retourne false si l'element est introuvable (id
/// invalide, playlist privee inaccessible...). Vit dans la couche UI (et
/// plus dans AppState) parce qu'il construit des ecrans.
Future<bool> openSharedItem(AppState state,
    {required String type, required String id}) async {
  final nav = state.navigator;
  switch (type) {
    case 'track':
      final track = state.findSharedTrack(id);
      if (track == null) return false;
      await state.playTrack(track);
      state.pushOverlay(const PlayerScreen());
      return true;
    case 'album':
      final album = state.findSharedAlbum(id);
      if (album == null) return false;
      final openAlbum = nav.onDesktopOpenAlbum;
      if (openAlbum != null) {
        openAlbum(album);
      } else {
        state.pushOverlay(AlbumScreen(album: album));
      }
      return true;
    case 'playlist':
      final playlist = await state.findSharedPlaylist(id);
      if (playlist == null) return false;
      final openPlaylist = nav.onDesktopOpenPlaylist;
      if (openPlaylist != null) {
        openPlaylist(playlist);
      } else {
        state.pushOverlay(PlaylistScreen(
          playlist: playlist,
          readOnly: !playlist.isOwnedByCurrentUser,
        ));
      }
      return true;
    default:
      return false;
  }
}
