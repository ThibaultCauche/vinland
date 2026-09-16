import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/discovered_album.dart';
import '../models/playlist.dart';
import '../models/pinned_item.dart';
import '../models/recent_play.dart';
import '../models/track.dart';
import '../services/deep_link_service.dart';
import 'desktop_album_view.dart';
import 'desktop_artist_discography_view.dart';
import 'desktop_artist_view.dart';
import 'desktop_background.dart';
import 'desktop_discovered_album_view.dart';
import 'desktop_hero_card.dart' show DesktopHeroMenuAction;
import 'desktop_sidebar.dart';
import 'desktop_player_bar.dart';
import 'desktop_home_view.dart';
import 'desktop_library_view.dart';
import 'desktop_search_view.dart';
import 'desktop_collection_view.dart';
import 'desktop_friends_view.dart';
import 'desktop_import_view.dart';
import 'desktop_friend_profile_view.dart';
import 'desktop_see_all_view.dart';
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
  // Vues "reculees" par _goBack, rejouables par _goForward -- comme
  // l'historique avant/arriere d'un navigateur. Vide a chaque nouvelle
  // navigation (_push) ou changement d'onglet, comme dans un vrai navigateur
  // (avancer une fois "hors piste" n'a plus de sens).
  final List<Widget> _forwardStack = [];

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

  void _push(Widget widget) {
    setState(() {
      _stack.add(widget);
      _forwardStack.clear();
    });
  }

  void _goBack() {
    if (_stack.isEmpty) return;
    setState(() => _forwardStack.add(_stack.removeLast()));
  }

  void _goForward() {
    if (_forwardStack.isEmpty) return;
    setState(() => _stack.add(_forwardStack.removeLast()));
  }

  void _clearStack() => setState(() {
        _stack.clear();
        _forwardStack.clear();
      });

  void _openAlbum(Album album, {String? filterArtist}) {
    _push(DesktopAlbumView(
      key: ValueKey('album-${album.id}-${filterArtist ?? ''}'),
      album: album,
      filterArtist: filterArtist,
      onOpenArtist: _openArtist,
    ));
  }

  void _openDiscoveredAlbum(
      {DiscoveredAlbum? album, int? albumId, String? filterArtist}) {
    _push(DesktopDiscoveredAlbumView(
      key: ValueKey(
          'discovered-album-${album?.id ?? albumId}-${filterArtist ?? ''}'),
      album: album,
      albumId: albumId,
      filterArtist: filterArtist,
      onOpenArtist: _openArtist,
    ));
  }

  void _openPlaylist(Playlist playlist) {
    final state = context.read<AppState>();
    // byId + trackIds.map (pas allTracks.where(...)) : ce dernier renvoie
    // les titres dans l'ordre de allTracks (globalement stable), pas celui
    // de la playlist -- ".first" tombait donc souvent sur le meme titre
    // (peu importe la playlist), montrant toujours la meme cover en-tete
    // (retour utilisateur). Meme correction deja appliquee a la grille de
    // la bibliotheque (voir DesktopLibraryView).
    final byId = {for (final t in state.allTracks) t.id: t};
    final tracks =
        playlist.trackIds.map((id) => byId[id]).whereType<Track>().toList();
    final trackCountLabel =
        '${playlist.trackIds.length} titre${playlist.trackIds.length > 1 ? 's' : ''}';
    // Cover aleatoire parmi les titres qui en ont vraiment une (pas juste
    // "le premier titre") -- meme apres avoir corrige l'ordre ci-dessus, le
    // premier titre restait souvent visuellement le meme d'une playlist a
    // l'autre (retour utilisateur), et un choix aleatoire est ce que
    // l'utilisateur a lui-meme suggere en remplacement.
    final coverCandidates = tracks
        .where((t) => t.coverPath != null && state.coverExists(t.coverPath))
        .toList();
    final coverPath = coverCandidates.isNotEmpty
        ? coverCandidates[Random().nextInt(coverCandidates.length)].coverPath
        : (tracks.isNotEmpty ? tracks.first.coverPath : null);
    _push(DesktopCollectionView(
          key: ValueKey('playlist-${playlist.id}'),
          title: playlist.name,
          subtitle: trackCountLabel,
          coverPath: coverPath,
          tracks: tracks,
          onOpenAlbum: _openAlbum,
          onOpenArtist: _openArtist,
          onRecordRecent: () => state.recordRecentPlay(RecentPlay(
                type: RecentPlayType.playlist,
                id: playlist.id,
                title: playlist.name,
                subtitle: trackCountLabel,
                coverPath: coverPath,
                playedAt: DateTime.now(),
              )),
          onShare: () => sharePlaylist(context, playlist),
          onSendToFriend: context.read<AppState>().shareInboxConfigured
              ? () => showSendToFriendDialog(context,
                  type: 'playlist',
                  title: playlist.name,
                  subtitle: trackCountLabel,
                  playlistForPrivacyCheck: playlist)
              : null,
          moreActions: [
            DesktopHeroMenuAction(
              label: state.isPinned(PinnedItemType.playlist, playlist.id)
                  ? "Désépingler de l'accueil"
                  : "Épingler à l'accueil",
              icon: state.isPinned(PinnedItemType.playlist, playlist.id)
                  ? Icons.push_pin
                  : Icons.push_pin_outlined,
              onTap: () => state.togglePin(PinnedItem(
                type: PinnedItemType.playlist,
                id: playlist.id,
                title: playlist.name,
                subtitle: trackCountLabel,
              )),
            ),
            DesktopHeroMenuAction(
              label: "Ajouter à la file d'attente",
              icon: Icons.playlist_add,
              onTap: () {
                for (final t in tracks) {
                  state.addToQueue(t);
                }
              },
            ),
            DesktopHeroMenuAction(
              label: 'Télécharger',
              icon: Icons.download_outlined,
              onTap: () => state.downloadTracksOffline(tracks),
            ),
            DesktopHeroMenuAction(
              label: playlist.isPublic ? 'Rendre privée' : 'Rendre publique',
              icon: playlist.isPublic ? Icons.lock_outline : Icons.public,
              onTap: () =>
                  state.setPlaylistPublic(playlist.id, !playlist.isPublic),
            ),
            DesktopHeroMenuAction(
              label: 'Supprimer',
              icon: Icons.delete_outline,
              destructive: true,
              onTap: () => _confirmDeletePlaylist(playlist),
            ),
          ],
        ));
  }

  Future<void> _confirmDeletePlaylist(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Supprimer la playlist ?',
            style: TextStyle(color: Colors.white)),
        content: Text('"${playlist.name}" sera supprimée définitivement.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AppState>().deletePlaylist(playlist.id);
      if (mounted) _goBack();
    }
  }

  void _openLikedSongs() {
    final state = context.read<AppState>();
    final tracks = state.likedTracksWithMissing;
    final trackCountLabel = '${tracks.length} titre${tracks.length > 1 ? 's' : ''}';
    _push(DesktopCollectionView(
          key: const ValueKey('liked-songs'),
          title: 'Titres likes',
          subtitle: 'Vos titres favoris',
          coverPath: tracks.isNotEmpty ? tracks.first.coverPath : null,
          tracks: tracks,
          onOpenAlbum: _openAlbum,
          onOpenArtist: _openArtist,
          onRecordRecent: () => state.recordRecentPlay(RecentPlay(
                type: RecentPlayType.playlist,
                id: kLikedSongsRecentId,
                title: 'Titres likés',
                subtitle: trackCountLabel,
                playedAt: DateTime.now(),
              )),
          moreActions: [
            DesktopHeroMenuAction(
              label: state.isPinned(
                      PinnedItemType.playlist, kLikedSongsRecentId)
                  ? "Désépingler de l'accueil"
                  : "Épingler à l'accueil",
              icon: state.isPinned(
                      PinnedItemType.playlist, kLikedSongsRecentId)
                  ? Icons.push_pin
                  : Icons.push_pin_outlined,
              onTap: () => state.togglePin(const PinnedItem(
                type: PinnedItemType.playlist,
                id: kLikedSongsRecentId,
                title: 'Titres likes',
                subtitle: 'Playlist',
              )),
            ),
          ],
        ));
  }

  void _openArtist(String artistName) {
    _push(DesktopArtistView(
      key: ValueKey('artist-$artistName'),
      artistName: artistName,
      onOpenAlbum: _openAlbum,
      onOpenDiscoveredAlbum: _openDiscoveredAlbum,
      onOpenDiscography: _openDiscography,
    ));
  }

  void _openDiscography(String artistName) {
    _push(DesktopArtistDiscographyView(
      key: ValueKey('discography-$artistName'),
      artistName: artistName,
      onOpenAlbum: _openAlbum,
      onOpenDiscoveredAlbum: _openDiscoveredAlbum,
    ));
  }

  void _openSearch() => setState(() {
        _tab = DesktopNavTab.search;
        _clearStack();
      });

  void _openFriendProfile(FriendProfile friend) {
    _push(DesktopFriendProfileView(friend: friend));
  }

  Future<void> _openFriendProfileByUsername(String username) async {
    final friend = await context.read<AppState>().resolveFriend(username);
    if (friend != null) _openFriendProfile(friend);
  }

  void _openSeeAll(String title, List<DesktopSeeAllItem> items) {
    _push(DesktopSeeAllView(title: title, items: items));
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
          onOpenFriendProfile: _openFriendProfileByUsername,
          onSeeAll: _openSeeAll,
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
                            top: DesktopGlass.titleBarHeight,
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
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: DesktopTitleBar(
                canGoBack: _stack.isNotEmpty,
                canGoForward: _forwardStack.isNotEmpty,
                onGoBack: _goBack,
                onGoForward: _goForward,
              ),
            ),
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
