import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/discovered_album.dart';
import '../models/playlist.dart';
import '../services/deep_link_service.dart';
import 'desktop_album_view.dart';
import 'desktop_artist_view.dart';
import 'desktop_background.dart';
import 'desktop_discovered_album_view.dart';
import 'desktop_sidebar.dart';
import 'desktop_player_bar.dart';
import 'desktop_home_view.dart';
import 'desktop_library_view.dart';
import 'desktop_search_view.dart';
import 'desktop_collection_view.dart';
import 'desktop_friends_view.dart';
import 'desktop_import_view.dart';
import 'desktop_friend_profile_view.dart';
import 'desktop_title_bar.dart';
import 'glass.dart';
import '../models/friend_profile.dart';

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

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    state.onDesktopOpenAlbum = _openAlbum;
    state.onDesktopOpenPlaylist = _openPlaylist;
  }

  @override
  void dispose() {
    final state = context.read<AppState>();
    state.onDesktopOpenAlbum = null;
    state.onDesktopOpenPlaylist = null;
    super.dispose();
  }

  void _push(Widget Function(VoidCallback onBack) builder) {
    late final Widget w;
    w = builder(() => setState(() => _stack.remove(w)));
    setState(() => _stack.add(w));
  }

  void _clearStack() => setState(() => _stack.clear());

  void _openAlbum(Album album, {String? filterArtist}) {
    _push((onBack) => DesktopAlbumView(
          key: ValueKey('album-${album.id}-${filterArtist ?? ''}'),
          album: album,
          filterArtist: filterArtist,
          onBack: onBack,
          onOpenArtist: _openArtist,
        ));
  }

  void _openDiscoveredAlbum(
      {DiscoveredAlbum? album, int? albumId, String? filterArtist}) {
    _push((onBack) => DesktopDiscoveredAlbumView(
          key: ValueKey(
              'discovered-album-${album?.id ?? albumId}-${filterArtist ?? ''}'),
          album: album,
          albumId: albumId,
          filterArtist: filterArtist,
          onBack: onBack,
          onOpenArtist: _openArtist,
        ));
  }

  void _openPlaylist(Playlist playlist) {
    final state = context.read<AppState>();
    final tracks =
        state.allTracks.where((t) => playlist.trackIds.contains(t.id)).toList();
    _push((onBack) => DesktopCollectionView(
          key: ValueKey('playlist-${playlist.id}'),
          title: playlist.name,
          subtitle: '${playlist.trackIds.length} titre(s)',
          coverPath: tracks.isNotEmpty ? tracks.first.coverPath : null,
          tracks: tracks,
          onBack: onBack,
          onOpenAlbum: _openAlbum,
          onOpenArtist: _openArtist,
          onShare: () => sharePlaylist(context, playlist),
          onSendToFriend: context.read<AppState>().shareInboxConfigured
              ? () => showSendToFriendDialog(context,
                  type: 'playlist',
                  title: playlist.name,
                  subtitle: '${playlist.trackIds.length} titre(s)',
                  playlistForPrivacyCheck: playlist)
              : null,
        ));
  }

  void _openLikedSongs() {
    final state = context.read<AppState>();
    final tracks = state.likedTracksWithMissing;
    _push((onBack) => DesktopCollectionView(
          key: const ValueKey('liked-songs'),
          title: 'Titres likes',
          subtitle: 'Vos titres favoris',
          coverPath: tracks.isNotEmpty ? tracks.first.coverPath : null,
          tracks: tracks,
          onBack: onBack,
          onOpenAlbum: _openAlbum,
          onOpenArtist: _openArtist,
        ));
  }

  void _openArtist(String artistName) {
    _push((onBack) => DesktopArtistView(
          key: ValueKey('artist-$artistName'),
          artistName: artistName,
          onBack: onBack,
          onOpenAlbum: _openAlbum,
          onOpenDiscoveredAlbum: _openDiscoveredAlbum,
        ));
  }

  void _openSearch() => setState(() {
        _tab = DesktopNavTab.search;
        _clearStack();
      });

  void _openFriendProfile(FriendProfile friend) {
    _push((onBack) => DesktopFriendProfileView(friend: friend, onBack: onBack));
  }

  Widget get _baseContent {
    switch (_tab) {
      case DesktopNavTab.home:
        return DesktopHomeView(
          onOpenAlbum: _openAlbum,
          onPlayTrackShelf: (t) {},
          onOpenArtist: _openArtist,
          onOpenLikedSongs: _openLikedSongs,
          onOpenPlaylist: _openPlaylist,
        );
      case DesktopNavTab.search:
        return DesktopSearchView(
          onOpenArtist: _openArtist,
          onOpenAlbum: _openAlbum,
          onOpenDiscoveredAlbum: _openDiscoveredAlbum,
        );
      case DesktopNavTab.library:
        return DesktopLibraryView(
          onOpenPlaylist: _openPlaylist,
          onOpenAlbum: _openAlbum,
        );
      case DesktopNavTab.friends:
        return DesktopFriendsView(onOpenFriend: _openFriendProfile);
      case DesktopNavTab.import_:
        return const DesktopImportView();
    }
  }

  /// Empile tous les ecrans traverses (onglet courant + pile de navigation
  /// locale) dans un IndexedStack plutot que de ne monter que le dernier :
  /// sans ca, ouvrir un album depuis la page artiste demontait entierement
  /// cette derniere (perte du ScrollController, retour tout en haut de la
  /// page une fois l'album referme) puisque Flutter detruit l'Element d'un
  /// widget qui cesse d'etre renvoye par build(), meme si le meme objet
  /// Widget reste garde en memoire dans _stack.
  Widget get _contentStack {
    if (_stack.isEmpty) return _baseContent;
    return IndexedStack(
      index: _stack.length,
      children: [_baseContent, ..._stack],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold fournit l'ancetre Material requis par les Slider (barre de
    // progression + volume du lecteur) -- sans lui ils levent une exception
    // a chaque frame. backgroundColor transparent : le fond vient de
    // DesktopBackground, pas de Scaffold.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DesktopBackground(
        child: Stack(
          children: [
            // Sidebar + contenu en plein-bord (jusqu'aux vrais bords de la
            // fenetre, haut ET bas) : la barre de titre et la barre de
            // lecture flottent par-dessus, donc rien n'est coupe net en
            // dessous/au-dessus d'elles -- chacun reserve lui-meme l'espace
            // necessaire (DesktopGlass.topInset / playerBarReserve) pour ne
            // pas demarrer derriere elles.
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // RepaintBoundary autour de chaque grande zone (sidebar,
                  // contenu, barre de lecture) : sans ca, aucun widget de
                  // l'appli n'etant lui-meme une frontiere de repaint, un
                  // repaint isole n'importe ou (ex: le slider de lecture qui
                  // tique 2 a 5x/seconde) remonte jusqu'a la racine et force
                  // TOUT l'ecran a se repeindre -- y compris les flous en
                  // verre depoli (BackdropFilter) de la sidebar/barre de
                  // lecture/fond, couteux a recalculer. Isoler ces zones
                  // evite qu'un tick du lecteur ne re-declenche ces flous.
                  RepaintBoundary(
                    child: DesktopSidebar(
                      activeTab: _tab,
                      onTabSelected: (t) => setState(() {
                        _tab = t;
                        _clearStack();
                      }),
                      onOpenPlaylist: _openPlaylist,
                      onOpenLikedSongs: _openLikedSongs,
                    ),
                  ),
                  Expanded(
                    child: RepaintBoundary(
                      // Pas de marge horizontale : le contenu va jusqu'aux
                      // bords reels de la fenetre. Le haut/bas sont geres
                      // par chaque vue de contenu elle-meme
                      // (DesktopGlass.topInset / playerBarReserve), sinon le
                      // contenu qui defile serait coupe net pile sous/sur
                      // la TopBar/barre de lecture plutot que derriere.
                      child: Stack(
                        children: [
                          Positioned.fill(child: _contentStack),
                          Positioned(
                            top: DesktopGlass.titleBarHeight + 4,
                            left: 0,
                            right: 0,
                            child: _TopBar(
                              onOpenSearch: _openSearch,
                              // L'onglet Recherche a deja son propre champ
                              // de saisie fonctionnel (DesktopSearchView) :
                              // la barre persistante ferait doublon avec
                              // lui.
                              showSearchBar: _stack.isEmpty &&
                                  _tab != DesktopNavTab.search,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Flottante par-dessus sidebar + contenu (pas de fond opaque :
            // elle n'a jamais besoin de rien cacher, c'est le contenu qui
            // doit se rendre invisible via DesktopGlass.topInset en dessous
            // d'elle).
            const Positioned(
                top: 0, left: 0, right: 0, child: DesktopTitleBar()),
            // Flottante par-dessus sidebar + contenu au bas de la fenetre --
            // son propre GlassPanel (flou + teinte) cache deja proprement
            // ce qui defile dessous, pas besoin d'un fondu separe comme
            // pour la TopBar.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: RepaintBoundary(
                child: DesktopPlayerBar(
                  onOpenAlbum: _openAlbum,
                  onOpenArtist: _openArtist,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onOpenSearch;
  final bool showSearchBar;
  const _TopBar({
    required this.onOpenSearch,
    required this.showSearchBar,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Barre de recherche persistante, au niveau du bouton de profil :
        // toujours visible/cliquable quel que soit l'onglet ou le defilement
        // en cours (contrairement a l'ancienne version, glissee en haut du
        // contenu scrollable de l'accueil, qui disparaissait au scroll).
        // Masquee sur l'onglet Recherche lui-meme, qui a deja son propre
        // champ de saisie fonctionnel juste en dessous -- sinon on se
        // retrouve avec deux barres de recherche empilees.
        // Expanded (et non un Align seul) : un Align non contraint dans un
        // Row prend toute la largeur disponible pour lui tout seul et pousse
        // l'avatar de profil hors de l'ecran.
        Expanded(
          child: !showSearchBar
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: onOpenSearch,
                        child: GlassPanel(
                          borderRadius: BorderRadius.circular(20),
                          blurSigma: 0,
                          tint: Colors.white.withOpacity(0.06),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: const SizedBox(
                            height: 36,
                            child: Row(
                              children: [
                                Icon(Icons.search,
                                    color: Colors.white54, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Titres, artistes, albums...',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
