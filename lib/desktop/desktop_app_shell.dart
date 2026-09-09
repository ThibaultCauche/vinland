import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../screens/settings_screen.dart';
import 'desktop_background.dart';
import 'desktop_sidebar.dart';
import 'desktop_player_bar.dart';
import 'desktop_home_view.dart';
import 'desktop_library_view.dart';
import 'desktop_search_view.dart';
import 'desktop_collection_view.dart';

/// Shell racine de l'app desktop : fond ambiant + sidebar + zone de contenu
/// + barre de lecture flottante. Sa propre pile de navigation locale (pas
/// celle d'AppState, pensee pour des ecrans mobiles pleine page).
class DesktopAppShell extends StatefulWidget {
  const DesktopAppShell({super.key});

  @override
  State<DesktopAppShell> createState() => _DesktopAppShellState();
}

class _DesktopAppShellState extends State<DesktopAppShell> {
  DesktopNavTab _tab = DesktopNavTab.home;
  final List<Widget> _stack = [];

  void _push(Widget Function(VoidCallback onBack) builder) {
    late final Widget w;
    w = builder(() => setState(() => _stack.remove(w)));
    setState(() => _stack.add(w));
  }

  void _clearStack() => setState(() => _stack.clear());

  void _openAlbum(Album album) {
    final state = context.read<AppState>();
    final tracks =
        state.allTracks.where((t) => album.trackIds.contains(t.id)).toList();
    _push((onBack) => DesktopCollectionView(
          title: album.title,
          subtitle: album.artist,
          coverPath: album.coverPath,
          tracks: tracks,
          isLiked: album.isSaved,
          onToggleLike: () => state.toggleLikeAlbum(album.id),
          onBack: onBack,
        ));
  }

  void _openPlaylist(Playlist playlist) {
    final state = context.read<AppState>();
    final tracks =
        state.allTracks.where((t) => playlist.trackIds.contains(t.id)).toList();
    _push((onBack) => DesktopCollectionView(
          title: playlist.name,
          subtitle: '${playlist.trackIds.length} titre(s)',
          coverPath: tracks.isNotEmpty ? tracks.first.coverPath : null,
          tracks: tracks,
          onBack: onBack,
        ));
  }

  void _openLikedSongs() {
    final state = context.read<AppState>();
    final tracks = state.likedTracks;
    _push((onBack) => DesktopCollectionView(
          title: 'Titres likes',
          subtitle: 'Vos titres favoris',
          coverPath: tracks.isNotEmpty ? tracks.first.coverPath : null,
          tracks: tracks,
          onBack: onBack,
        ));
  }

  void _openArtist(String artistName) {
    final state = context.read<AppState>();
    final tracks =
        state.allTracks.where((t) => t.artist == artistName).toList();
    _push((onBack) => DesktopCollectionView(
          title: artistName,
          subtitle: 'Artiste',
          coverPath: tracks.isNotEmpty ? tracks.first.coverPath : null,
          tracks: tracks,
          onBack: onBack,
        ));
  }

  Widget get _content {
    if (_stack.isNotEmpty) return _stack.last;
    switch (_tab) {
      case DesktopNavTab.home:
        return DesktopHomeView(
          onOpenAlbum: _openAlbum,
          onPlayTrackShelf: (t) {},
          onOpenArtist: _openArtist,
        );
      case DesktopNavTab.search:
        return const DesktopSearchView();
      case DesktopNavTab.library:
        return DesktopLibraryView(
          onOpenPlaylist: _openPlaylist,
          onOpenAlbum: _openAlbum,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();

    // Scaffold fournit l'ancetre Material requis par les Slider (barre de
    // progression + volume du lecteur) -- sans lui ils levent une exception
    // a chaque frame. backgroundColor transparent : le fond vient de
    // DesktopBackground, pas de Scaffold.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DesktopBackground(
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DesktopSidebar(
                    activeTab: _tab,
                    onTabSelected: (t) => setState(() {
                      _tab = t;
                      _clearStack();
                    }),
                    onOpenPlaylist: _openPlaylist,
                    onOpenLikedSongs: _openLikedSongs,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 12, 12, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TopBar(state: state),
                          const SizedBox(height: 16),
                          Expanded(child: _content),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const DesktopPlayerBar(),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final AppState state;
  const _TopBar({required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        GestureDetector(
          onTap: () => _showProfileMenu(context, state),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF3E3E3E),
            child: Text(
              state.userName?.substring(0, 1).toUpperCase() ?? 'U',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  void _showProfileMenu(BuildContext context, AppState state) {
    final navigator = Navigator.of(context, rootNavigator: true);
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 60, 20, 0),
      color: const Color(0xFF1E1E1E),
      items: [
        PopupMenuItem(
          child:
              const Text('Parametres', style: TextStyle(color: Colors.white)),
          onTap: () {
            Future.microtask(() => navigator.push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ));
          },
        ),
        PopupMenuItem(
          child: const Text('Se deconnecter',
              style: TextStyle(color: Colors.white)),
          onTap: () => state.logout(),
        ),
      ],
    );
  }
}
