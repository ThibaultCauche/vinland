import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/pinned_item.dart';
import '../models/playlist.dart';
import '../models/recent_play.dart';
import '../models/track.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/smooth_scroll.dart';
import '../widgets/sync_status_banner.dart';
import '../widgets/cover_image.dart';
import '../widgets/user_avatar.dart';
import 'desktop_horizontal_shelf.dart';
import 'desktop_see_all_view.dart';
import 'glass.dart';

/// Accueil desktop : shelves horizontales dans des cartes en verre, comme
/// la home mobile mais redimensionnee pour un grand ecran.
class DesktopHomeView extends StatefulWidget {
  final ValueChanged<Album> onOpenAlbum;
  final ValueChanged<Track> onPlayTrackShelf;
  final ValueChanged<String> onOpenArtist;
  final VoidCallback onOpenLikedSongs;
  final ValueChanged<Playlist> onOpenPlaylist;
  final ValueChanged<String> onOpenFriendProfile;
  final void Function(String title, List<DesktopSeeAllItem> items) onSeeAll;

  const DesktopHomeView({
    super.key,
    required this.onOpenAlbum,
    required this.onPlayTrackShelf,
    required this.onOpenArtist,
    required this.onOpenLikedSongs,
    required this.onOpenPlaylist,
    required this.onOpenFriendProfile,
    required this.onSeeAll,
  });

  @override
  State<DesktopHomeView> createState() => _DesktopHomeViewState();
}

class _DesktopHomeViewState extends State<DesktopHomeView> {
  final _scrollController = SmoothScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  ValueChanged<Album> get onOpenAlbum => widget.onOpenAlbum;
  ValueChanged<String> get onOpenArtist => widget.onOpenArtist;

  void _openRecentPlay(BuildContext context, AppState state, RecentPlay entry) {
    switch (entry.type) {
      case RecentPlayType.album:
        final albums = state.albums.where((a) => a.id == entry.id);
        if (albums.isNotEmpty) onOpenAlbum(albums.first);
        break;
      case RecentPlayType.playlist:
        if (entry.id == kLikedSongsRecentId) {
          widget.onOpenLikedSongs();
          return;
        }
        final playlists = state.playlists.where((p) => p.id == entry.id);
        if (playlists.isNotEmpty) widget.onOpenPlaylist(playlists.first);
        break;
      case RecentPlayType.artist:
        onOpenArtist(entry.id);
        break;
      case RecentPlayType.friend:
        widget.onOpenFriendProfile(entry.id);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Les etageres viennent de AppState (pre-calculees, stables pendant une
    // synchro -- voir AppState._refreshHomeShelves) plutot que recalculees
    // ici a partir de albums/allTracks, qui grossissent en continu pendant
    // le chargement.
    return Selector<
        AppState,
        (
          List<Track>,
          List<(String, String?)>,
          List<Album>,
          List<Album>,
          String?,
          List<RecentPlay>,
          bool
        )>(
      selector: (_, state) => (
        state.homeWeeklyTracks,
        state.homeTopArtists,
        state.homeDiscoveryAlbums,
        state.homeNewOnServerAlbums,
        state.userName,
        state.homeShelfEntries,
        state.isSyncing,
      ),
      builder: (context, data, __) {
        final (
          weeklyTracks,
          topArtists,
          discoveryAlbums,
          newOnServer,
          userName,
          recentPlays,
          isSyncing
        ) = data;
        final state = context.read<AppState>();

        return ListView(
          key: const Key('desktopHomeScrollView'),
          controller: _scrollController,
          padding: const EdgeInsets.only(
              top: DesktopGlass.topInset,
              bottom: DesktopGlass.playerBarReserve),
          children: [
            Text(
              'Bonjour${userName != null ? ', $userName' : ''}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            // Pendant une synchro normale, seul le petit cercle vert du
            // TopBar (a cote de l'avatar) suffit -- ce bandeau ne reapparait
            // que pour l'etat d'erreur (NAS injoignable), qui merite d'etre
            // vu et a un bouton "Reessayer".
            if (!isSyncing) const SyncStatusBanner(),
            if (recentPlays.isNotEmpty) ...[
              _recentPlayGrid(context, state, recentPlays),
              const SizedBox(height: 8),
            ],
            _sectionTitle('Écoutés cette semaine',
                onSeeAll: weeklyTracks.isEmpty
                    ? null
                    : () => widget.onSeeAll('Écoutés cette semaine',
                        _trackItems(context, weeklyTracks))),
            _trackShelf(context, weeklyTracks),
            _sectionTitle('Artistes du moment',
                onSeeAll: topArtists.isEmpty
                    ? null
                    : () => widget.onSeeAll(
                        'Artistes du moment', _artistItems(topArtists))),
            _artistShelf(context, topArtists),
            _sectionTitle('Découverte',
                onSeeAll: discoveryAlbums.isEmpty
                    ? null
                    : () => widget.onSeeAll(
                        'Découverte', _albumItems(discoveryAlbums))),
            _albumShelf(context, discoveryAlbums),
            _sectionTitle('Nouveautés du NAS',
                onSeeAll: newOnServer.isEmpty
                    ? null
                    : () => widget.onSeeAll(
                        'Nouveautés du NAS', _albumItems(newOnServer))),
            _albumShelf(context, newOnServer),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(String text, {VoidCallback? onSeeAll}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 12),
        child: Row(
          children: [
            Text(text,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            if (onSeeAll != null)
              TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Tout afficher',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      );

  List<DesktopSeeAllItem> _trackItems(
      BuildContext context, List<Track> tracks) {
    final state = context.read<AppState>();
    return [
      for (final t in tracks)
        DesktopSeeAllItem(
          title: t.title,
          subtitle: t.artist,
          coverPath: t.coverPath,
          onTap: () => state.playTrack(t, trackList: tracks),
        ),
    ];
  }

  List<DesktopSeeAllItem> _albumItems(List<Album> albums) => [
        for (final a in albums)
          DesktopSeeAllItem(
            title: a.title,
            subtitle: a.artist,
            coverPath: a.coverPath,
            onTap: () => onOpenAlbum(a),
          ),
      ];

  List<DesktopSeeAllItem> _artistItems(
          List<(String artist, String? coverPath)> picks) =>
      [
        for (final (artist, coverPath) in picks)
          DesktopSeeAllItem(
            title: artist,
            coverPath: coverPath,
            circle: true,
            onTap: () => onOpenArtist(artist),
          ),
      ];

  Widget _emptyShelf(String text) => SizedBox(
        height: 60,
        child: Center(
            child: Text(text, style: const TextStyle(color: Colors.white38))),
      );

  Widget _recentPlayGrid(
      BuildContext context, AppState state, List<RecentPlay> entries) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // right: 24 -- sans ca la derniere colonne touchait pile le bord de
      // la fenetre (SliverGridDelegateWithMaxCrossAxisExtent etire les
      // tuiles pour remplir toute la largeur offerte), retour utilisateur.
      padding: const EdgeInsets.only(right: 24),
      // maxCrossAxisExtent (et non un nombre de colonnes fixe) : la tuile ne
      // contient qu'une petite cover 48x48 + un titre sur une ligne, un
      // nombre de colonnes fixe l'etirait sur toute la largeur disponible
      // (tres large avec beaucoup de vide a droite) -- ici chaque tuile
      // plafonne a une largeur raisonnable et de nouvelles colonnes
      // apparaissent plutot que d'etirer les tuiles existantes.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        childAspectRatio: 4.2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return _RecentPlayTile(
          entry: entry,
          onTap: () => _openRecentPlay(context, state, entry),
        );
      },
    );
  }

  Widget _trackShelf(BuildContext context, List<Track> tracks) {
    if (tracks.isEmpty)
      return _emptyShelf('Pas encore assez d\'écoutes cette semaine');
    final state = context.read<AppState>();
    return DesktopHorizontalShelf(
      height: 210,
      itemCount: tracks.length,
      itemBuilder: (context, i) {
        final track = tracks[i];
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: SizedBox(
            width: 166,
            child: DesktopHoverable(
              onTap: () => state.playTrack(track, trackList: tracks),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DesktopShelfCover(coverPath: track.coverPath, size: 150),
                    const SizedBox(height: 8),
                    Text(track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    Text(track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _albumShelf(BuildContext context, List<Album> albums) {
    if (albums.isEmpty) return _emptyShelf('Rien a afficher pour le moment');
    return DesktopHorizontalShelf(
      height: 210,
      itemCount: albums.length,
      itemBuilder: (context, i) {
        final album = albums[i];
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: SizedBox(
            width: 166,
            child: DesktopHoverable(
              onTap: () => onOpenAlbum(album),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DesktopShelfCover(coverPath: album.coverPath, size: 150),
                    const SizedBox(height: 8),
                    Text(album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    Text(album.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _artistShelf(
      BuildContext context, List<(String artist, String? coverPath)> picks) {
    if (picks.isEmpty) {
      return _emptyShelf('Écoutez de la musique pour voir vos artistes ici');
    }

    return DesktopHorizontalShelf(
      height: 160,
      itemCount: picks.length,
      itemBuilder: (context, i) {
        final (artist, coverPath) = picks[i];
        // Meme forme de surbrillance que la page recherche (rectangle
        // arrondi derriere toute la carte) -- un cercle limite juste a
        // l'avatar avait ete essaye, mais ce n'etait pas le rendu voulu.
        return Padding(
          padding: const EdgeInsets.only(right: 20),
          child: SizedBox(
            width: 104,
            child: DesktopHoverable(
              onTap: () => onOpenArtist(artist),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ArtistAvatar(
                      artistName: artist, fallbackCoverPath: coverPath, size: 96),
                  const SizedBox(height: 8),
                  Text(artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Une des 8 tuiles "recemment ecoute" (equivalent desktop de la grille 2
/// colonnes de HomeScreen mobile, mais sur 4 colonnes vu la largeur
/// disponible).
class _RecentPlayTile extends StatelessWidget {
  final RecentPlay entry;
  final VoidCallback onTap;
  const _RecentPlayTile({required this.entry, required this.onTap});

  bool _isPinned(AppState state) {
    final type = switch (entry.type) {
      RecentPlayType.album => PinnedItemType.album,
      RecentPlayType.playlist => PinnedItemType.playlist,
      RecentPlayType.artist => PinnedItemType.artist,
      RecentPlayType.friend => null,
    };
    if (type == null) return false;
    return state.isPinned(type, entry.id);
  }

  @override
  Widget build(BuildContext context) {
    final pinned = _isPinned(context.watch<AppState>());
    return DesktopHoverable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
      child: Stack(
        // expand : sans ca, ce Container (sans hauteur propre) se
        // retrecirait a la taille de son contenu au lieu de remplir la
        // cellule de la grille -- un Stack donne des contraintes "loose" a
        // ses enfants non-Positioned par defaut.
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                _RecentPlayCover(entry: entry),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (pinned)
            Positioned(
              top: 4,
              right: 4,
              // Rotation -45deg puis miroir horizontal : la rotation seule
              // pointait vers le sud-est, pas le sud-ouest voulu (retour
              // utilisateur explicite).
              child: Transform.flip(
                flipX: true,
                child: Transform.rotate(
                  angle: -pi / 4,
                  child: const Icon(Icons.push_pin,
                      color: Color(0xFF1DB954), size: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentPlayCover extends StatelessWidget {
  final RecentPlay entry;
  const _RecentPlayCover({required this.entry});

  IconData get _fallbackIcon {
    switch (entry.type) {
      case RecentPlayType.album:
        return Icons.album;
      case RecentPlayType.playlist:
        return entry.id == kLikedSongsRecentId
            ? Icons.favorite
            : Icons.queue_music;
      case RecentPlayType.artist:
        return Icons.person;
      case RecentPlayType.friend:
        return Icons.person;
    }
  }

  // Circulaire pour artiste/ami, sinon carre arrondi sur les 4 coins -- la
  // cover n'est plus collee au bord gauche de la tuile (SizedBox de 8 dans
  // _RecentPlayTile, retour utilisateur), donc plus de raison de ne garder
  // que les coins de droite arrondis comme avant.
  BorderRadius get _shape =>
      entry.type == RecentPlayType.artist || entry.type == RecentPlayType.friend
          ? const BorderRadius.all(Radius.circular(48))
          : BorderRadius.circular(DesktopGlass.radiusSm);

  @override
  Widget build(BuildContext context) {
    // Avatar d'ami : image reseau via AvatarService (username), pas une
    // cover locale -- rendu different du reste (voir UserAvatar), d'ou ce
    // cas a part plutot qu'un chemin de cover qui n'existe pas pour un ami.
    if (entry.type == RecentPlayType.friend) {
      return ClipRRect(
        borderRadius: _shape,
        child: UserAvatar(username: entry.id, size: 48),
      );
    }

    // "Titres likes" : meme vert que le mini-player plutot que le meme gris
    // neutre que tout le reste. Une vraie Playlist se rabat sur
    // PlaylistCover (Playlist n'a pas de cover dediee cote Navidrome --
    // collage a partir des covers de ses propres titres, comme Spotify).
    // Meme fix que la home mobile (retour utilisateur).
    if (entry.type == RecentPlayType.playlist) {
      if (entry.id == kLikedSongsRecentId) {
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: const Color(0xFF1DB954), borderRadius: _shape),
          child: const Icon(Icons.favorite, color: Colors.white, size: 20),
        );
      }
      final playlist = context
          .read<AppState>()
          .playlists
          .cast<Playlist?>()
          .firstWhere((p) => p?.id == entry.id, orElse: () => null);
      if (playlist != null) {
        return PlaylistCover(playlist: playlist, size: 48, borderRadius: _shape);
      }
    }

    // Vraie photo d'artiste -- necessaire pour une tuile epinglee (pas de
    // coverPath, voir PinnedItem), et strictement meilleur pour une entree
    // "recemment ecoute" classique aussi.
    if (entry.type == RecentPlayType.artist) {
      return ClipRRect(
        borderRadius: _shape,
        child: ArtistAvatar(
          artistName: entry.id,
          fallbackCoverPath: entry.coverPath,
          size: 48,
        ),
      );
    }

    // Album : resout la cover REELLE depuis la bibliotheque par id plutot
    // que de se fier au coverPath stocke dans l'entree -- une tuile
    // epinglee n'en a pas du tout.
    if (entry.type == RecentPlayType.album) {
      final album = context
          .read<AppState>()
          .albums
          .cast<Album?>()
          .firstWhere((a) => a?.id == entry.id, orElse: () => null);
      if (album?.coverPath != null &&
          context.read<AppState>().coverExists(album!.coverPath)) {
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: _shape,
            image: DecorationImage(
              image: coverImageProvider(context,
                  path: album.coverPath!, width: 48, height: 48),
              fit: BoxFit.cover,
              onError: (_, __) {},
            ),
          ),
        );
      }
    }

    final path = entry.coverPath;
    final exists = context.read<AppState>().coverExists(path);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF3E3E3E),
        borderRadius: _shape,
        image: exists && path != null
            ? DecorationImage(
                image: coverImageProvider(context,
                    path: path, width: 48, height: 48),
                fit: BoxFit.cover,
                onError: (_, __) {},
              )
            : null,
      ),
      child:
          !exists ? Icon(_fallbackIcon, color: Colors.white54, size: 18) : null,
    );
  }
}

/// Cover carree utilisee par les etageres de l'accueil -- publique pour etre
/// reutilisee par DesktopSeeAllView (grille "Tout afficher").
class DesktopShelfCover extends StatelessWidget {
  final String? coverPath;
  final double size;
  const DesktopShelfCover({super.key, required this.coverPath, required this.size});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final exists = context.read<AppState>().coverExists(path);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
        image: exists && path != null
            ? DecorationImage(
                image: coverImageProvider(context,
                    path: path, width: size, height: size),
                fit: BoxFit.cover,
                onError: (_, __) {},
              )
            : null,
      ),
      child: !exists
          ? const Icon(Icons.album, color: Colors.white54, size: 36)
          : null,
    );
  }
}
