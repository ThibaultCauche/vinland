import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/pinned_item.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/recent_play.dart';
import '../screens/settings_screen.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import 'playlist_screen.dart';
import '../screens/missing_tracks_screen.dart';
import '../services/music_service.dart';
import '../widgets/sync_status_banner.dart';
import '../widgets/cover_image.dart';
import '../widgets/user_avatar.dart';
import '../widgets/album_options_sheet.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/artist_options_sheet.dart';
import '../widgets/bottom_sheet_common.dart';
import '../widgets/playlist_options_sheet.dart';
import '../widgets/playlist_cover.dart';
import 'friend_profile_screen.dart';
import 'search_screen.dart';
import '../widgets/bottom_bar_reserve.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
          List<Map<String, dynamic>>,
          int,
          List<RecentPlay>
        )>(
      selector: (_, state) => (
        state.homeWeeklyTracks,
        state.homeTopArtists,
        state.homeDiscoveryAlbums,
        state.homeNewOnServerAlbums,
        state.userName,
        state.missingTracks,
        state.avatarVersion,
        state.homeShelfEntries,
      ),
      builder: (context, data, child) {
        final (
          weeklyTracks,
          topArtists,
          discoveryAlbums,
          newOnServer,
          userName,
          missingTracks,
          avatarVersion,
          _,
        ) = data;
        final state = context.read<AppState>();
        return SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Barre fixe (avatar + recherche) : seul endroit d'acces a la
              // recherche sur mobile, elle doit rester joignable quel que
              // soit le defilement plutot que scroller avec le contenu
              // (retour utilisateur).
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _showProfileMenu(context),
                      child: UserAvatar(
                        username: userName ?? 'U',
                        size: 36,
                        cacheBust: avatarVersion,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => state.pushOverlay(const SearchScreen()),
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(width: 12),
                              Icon(Icons.search,
                                  color: Colors.white54, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Rechercher des titres, artistes...',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const SyncIndicator(),
                  ],
                ),
              ),
              Expanded(
                child: CustomScrollView(
                  key: const Key('mobileHomeScrollView'),
                  slivers: [
                    const SliverToBoxAdapter(child: SyncStatusBanner()),
                    _buildSectionTitle('Récemment écouté'),
                    _buildRecentlyPlayed(state),
                    _buildSectionTitle('Écoutés cette semaine'),
                    _buildWeeklyTracks(state, weeklyTracks),
                    _buildSectionTitle('Artistes du moment'),
                    _buildTopArtists(state, topArtists),
                    _buildSectionTitle('Découverte'),
                    _buildDiscovery(state, discoveryAlbums),
                    _buildSectionTitle('Nouveautés du NAS'),
                    _buildNewOnServer(state, newOnServer),
                    SliverToBoxAdapter(
                        child: SizedBox(height: bottomBarReserve(context))),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(String text) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(text, style: const TextStyle(color: Colors.white38)),
        ),
      ),
    );
  }

  Widget _buildRecentlyPlayed(AppState state) {
    // Tuiles epinglees + recemment ecoute, deja fusionnees/limitees a 10.
    final recentPlays = state.homeShelfEntries;

    if (recentPlays.isEmpty) {
      return _buildEmpty('Commencez à écouter de la musique');
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 2.8,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final entry = recentPlays[index];
            final pinned = _isEntryPinned(state, entry);

            return GestureDetector(
              onTap: () => _openRecentPlay(context, state, entry),
              onLongPress: () => _openRecentPlayOptions(context, state, entry),
              child: Stack(
                // expand : sans ca, les enfants non-Positioned d'un Stack
                // recoivent des contraintes "loose" au lieu des contraintes
                // "tight" de la cellule de la grille -- ce Container(height:
                // 56) etait avant automatiquement etire/centre par la grille,
                // le Stack le laissait a sa hauteur demandee et colle en haut
                // au lieu de rester centre, supprimant la petite marge du
                // haut (retour utilisateur).
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        _RecentPlayCover(entry: entry),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  entry.subtitle,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11),
                                ),
                              ],
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
                      // Rotation -45deg puis miroir horizontal : la rotation
                      // seule pointait vers le sud-est, pas le sud-ouest
                      // voulu (retour utilisateur explicite).
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
          },
          childCount: recentPlays.length,
        ),
      ),
    );
  }

  /// Albums presents sur le NAS mais pas encore likes (voir
  /// AppState._refreshHomeShelves pour le calcul, stable tant qu'aucune
  /// synchro n'est en cours).
  Widget _buildDiscovery(AppState state, List<Album> picks) {
    if (picks.isEmpty) {
      return _buildEmpty('Tout est déjà liké !');
    }
    return _buildAlbumShelf(state, picks);
  }

  /// Derniers albums ajoutes au NAS (base sur la date d'ajout Navidrome des
  /// titres qui les composent).
  Widget _buildNewOnServer(AppState state, List<Album> picks) {
    if (picks.isEmpty) {
      return _buildEmpty('Aucune date d\'ajout disponible (resynchronisez)');
    }
    return _buildAlbumShelf(state, picks);
  }

  Widget _buildAlbumShelf(AppState state, List<Album> picks) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 190,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: picks.length,
          itemBuilder: (context, index) {
            final album = picks[index];
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 130,
                child: GestureDetector(
                  onTap: () => state.pushOverlay(AlbumScreen(album: album)),
                  onLongPress: () => showAlbumOptions(context, album),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        height: 130,
                        child: _DiscoveryCover(coverPath: album.coverPath),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        album.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        album.artist,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Titres les plus ecoutes au cours des 7 derniers jours.
  Widget _buildWeeklyTracks(AppState state, List<Track> picks) {
    if (picks.isEmpty) {
      return _buildEmpty('Pas encore assez d\'écoutes cette semaine');
    }

    return SliverToBoxAdapter(
      child: SizedBox(
        height: 190,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: picks.length,
          itemBuilder: (context, index) {
            final track = picks[index];
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 130,
                child: GestureDetector(
                  onTap: () => state.playTrack(track, trackList: picks),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        height: 130,
                        child: _DiscoveryCover(coverPath: track.coverPath),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        track.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        track.artist,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Artistes cumulant le plus d'ecoutes dans la bibliotheque locale.
  Widget _buildTopArtists(
      AppState state, List<(String artist, String? coverPath)> picks) {
    if (picks.isEmpty) {
      return _buildEmpty('Écoutez de la musique pour voir vos artistes ici');
    }

    return SliverToBoxAdapter(
      // Hauteur ajustee au contenu reel (avatar 88 + marge 8 + une ligne de
      // texte) au lieu de 150 -- le Column ne s'etirait pas pour combler la
      // hauteur du SizedBox, laissant ~35px de vide sous le nom de chaque
      // artiste (retour utilisateur).
      child: SizedBox(
        height: 124,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: picks.length,
          itemBuilder: (context, index) {
            final (artist, coverPath) = picks[index];
            return Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 96,
                child: GestureDetector(
                  onTap: () =>
                      state.pushOverlay(ArtistScreen(artistName: artist)),
                  onLongPress: () =>
                      showArtistOptions(context, artist, coverPath: coverPath),
                  child: Column(
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: 88,
                          height: 88,
                          child:
                              _DiscoveryCover(coverPath: coverPath, size: 88),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        artist,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Pour la petite punaise affichee sur une tuile epinglee -- convertit le
  /// type RecentPlay (utilise pour l'affichage fusionne, voir
  /// AppState.homeShelfEntries) vers le type PinnedItem correspondant.
  bool _isEntryPinned(AppState state, RecentPlay entry) {
    final type = switch (entry.type) {
      RecentPlayType.album => PinnedItemType.album,
      RecentPlayType.playlist => PinnedItemType.playlist,
      RecentPlayType.artist => PinnedItemType.artist,
      RecentPlayType.friend => null,
    };
    if (type == null) return false;
    return state.isPinned(type, entry.id);
  }

  void _openRecentPlay(BuildContext context, AppState state, RecentPlay entry) {
    switch (entry.type) {
      case RecentPlayType.album:
        final albums = state.albums.where((a) => a.id == entry.id);
        if (albums.isNotEmpty) {
          state.pushOverlay(AlbumScreen(album: albums.first));
        }
        break;
      case RecentPlayType.playlist:
        if (entry.id == kLikedSongsRecentId) {
          // Ouvre la page "Titres likes" de la bibliotheque plutot que de
          // lancer direct la lecture -- coherent avec toutes les autres
          // tuiles (album/playlist/artiste), qui ouvrent leur page au lieu
          // de jouer un titre au hasard (retour utilisateur).
          state.setTab(1);
          return;
        }
        final playlists = state.playlists.where((p) => p.id == entry.id);
        if (playlists.isNotEmpty) {
          state.pushOverlay(PlaylistScreen(playlist: playlists.first));
        }
        break;
      case RecentPlayType.artist:
        state.pushOverlay(ArtistScreen(artistName: entry.id));
        break;
      case RecentPlayType.friend:
        state.resolveFriend(entry.id).then((friend) {
          if (friend != null)
            state.pushOverlay(FriendProfileScreen(friend: friend));
        });
        break;
    }
  }

  /// Meme resolution que _openRecentPlay, mais ouvre la feuille d'options au
  /// lieu de naviguer -- pas d'equivalent pour un ami (pas un container
  /// album/playlist/artiste). "Titres likes" n'a qu'une seule option
  /// possible (epingler), pas un vrai Playlist pour le reste.
  void _openRecentPlayOptions(
      BuildContext context, AppState state, RecentPlay entry) {
    switch (entry.type) {
      case RecentPlayType.album:
        final albums = state.albums.where((a) => a.id == entry.id);
        if (albums.isNotEmpty) showAlbumOptions(context, albums.first);
        break;
      case RecentPlayType.playlist:
        if (entry.id == kLikedSongsRecentId) {
          _showLikedSongsPinOptions(context, state);
          return;
        }
        final playlists = state.playlists.where((p) => p.id == entry.id);
        if (playlists.isNotEmpty) {
          showPlaylistOptions(context, playlists.first);
        }
        break;
      case RecentPlayType.artist:
        showArtistOptions(context, entry.id, coverPath: entry.coverPath);
        break;
      case RecentPlayType.friend:
        break;
    }
  }

  void _showLikedSongsPinOptions(BuildContext context, AppState state) {
    final pinned = state.isPinned(PinnedItemType.playlist, kLikedSongsRecentId);
    showOptionsSheet(context,
        builder: (ctx) => [
              SheetTile(
                icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
                label: pinned
                    ? "Desepingler de l'accueil"
                    : "Epingler a l'accueil",
                onTap: () {
                  Navigator.pop(ctx);
                  state.togglePin(const PinnedItem(
                    type: PinnedItemType.playlist,
                    id: kLikedSongsRecentId,
                    title: 'Titres likes',
                    subtitle: 'Playlist',
                  ));
                },
              ),
              const SizedBox(height: 8),
            ]);
  }

  void _showProfileMenu(BuildContext context) {
    final state = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: UserAvatar(
                  username: state.userName ?? 'U',
                  size: 40,
                  cacheBust: state.avatarVersion,
                ),
                title: Text(
                  state.userName ?? 'Utilisateur',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              const Divider(color: Color(0xFF2A2A2A)),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.white54),
                title: const Text('Paramètres',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  state.pushOverlay(const SettingsScreen());
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.playlist_remove, color: Colors.orange),
                title: const Text('Titres manquants',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  '${state.missingTracks.length} titre(s) à importer',
                  style: const TextStyle(color: Colors.white54),
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (state.missingTracks.isNotEmpty) {
                    state.pushOverlay(const MissingTracksScreen());
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Aucun titre manquant')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.white54),
                title: const Text('Se déconnecter',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  state.logout();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoveryCover extends StatelessWidget {
  final String? coverPath;
  final double size;
  const _DiscoveryCover({this.coverPath, this.size = 130});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final exists = context.read<MusicService>().coverExists(path);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        image: exists && path != null
            ? DecorationImage(
                image: coverImageProvider(context,
                    path: path, width: size, height: size),
                fit: BoxFit.cover,
                onError: (_, __) {},
              )
            : null,
      ),
      child: exists != true
          ? const Center(
              child: Icon(Icons.album, color: Colors.white54, size: 40),
            )
          : null,
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

  BorderRadius get _shape =>
      entry.type == RecentPlayType.artist || entry.type == RecentPlayType.friend
          ? const BorderRadius.all(Radius.circular(28))
          : const BorderRadius.horizontal(left: Radius.circular(6));

  @override
  Widget build(BuildContext context) {
    // Avatar d'ami : image reseau via AvatarService (username), pas une
    // cover locale -- voir DesktopHomeView._RecentPlayCover pour la meme
    // logique cote desktop.
    if (entry.type == RecentPlayType.friend) {
      return ClipRRect(
        borderRadius: _shape,
        child: UserAvatar(username: entry.id, size: 56),
      );
    }

    // "Titres likes" : meme vert que le coeur du mini-player plutot que le
    // meme gris neutre que tout le reste (retour utilisateur, rend l'app
    // moins terne). Une vraie Playlist normale se rabat sur PlaylistCover
    // (Playlist n'a pas de cover dediee cote Navidrome -- collage a partir
    // des covers de ses propres titres, comme Spotify).
    if (entry.type == RecentPlayType.playlist) {
      if (entry.id == kLikedSongsRecentId) {
        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF1DB954),
            borderRadius: _shape,
          ),
          child: const Icon(Icons.favorite, color: Colors.white),
        );
      }
      final playlist = context
          .read<AppState>()
          .playlists
          .cast<Playlist?>()
          .firstWhere((p) => p?.id == entry.id, orElse: () => null);
      if (playlist != null) {
        return PlaylistCover(
            playlist: playlist, size: 56, borderRadius: _shape);
      }
    }

    // Vraie photo d'artiste (pas de cover generique) -- necessaire pour une
    // tuile epinglee, qui ne transporte pas de coverPath (voir PinnedItem),
    // et strictement meilleur pour une tuile "recemment ecoute" classique
    // aussi.
    if (entry.type == RecentPlayType.artist) {
      return ClipRRect(
        borderRadius: _shape,
        child: ArtistAvatar(
          artistName: entry.id,
          fallbackCoverPath: entry.coverPath,
          size: 56,
        ),
      );
    }

    // Album : resout la cover REELLE depuis la bibliotheque par id plutot
    // que de se fier au coverPath stocke dans l'entree -- une tuile epinglee
    // n'en a pas du tout (voir PinnedItem), et ca evite aussi une cover
    // figee/perimee pour une entree "recemment ecoute" classique.
    if (entry.type == RecentPlayType.album) {
      final album = context
          .read<AppState>()
          .albums
          .cast<Album?>()
          .firstWhere((a) => a?.id == entry.id, orElse: () => null);
      if (album?.coverPath != null) {
        final exists =
            context.read<MusicService>().coverExists(album!.coverPath);
        if (exists) {
          return Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: _shape,
              image: DecorationImage(
                image: coverImageProvider(context,
                    path: album.coverPath!, width: 56, height: 56),
                fit: BoxFit.cover,
                onError: (_, __) {},
              ),
            ),
          );
        }
      }
    }

    final path = entry.coverPath;
    final exists = context.read<MusicService>().coverExists(path);

    if (exists && path != null) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: _shape,
          image: DecorationImage(
            image:
                coverImageProvider(context, path: path, width: 56, height: 56),
            fit: BoxFit.cover,
            onError: (_, __) {},
          ),
        ),
      );
    }
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF3E3E3E),
        borderRadius: _shape,
      ),
      child: Icon(_fallbackIcon, color: Colors.white54),
    );
  }
}
