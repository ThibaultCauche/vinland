import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/track.dart';
import '../models/recent_play.dart';
import '../screens/settings_screen.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import 'playlist_screen.dart';
import '../screens/missing_tracks_screen.dart';
import '../services/music_service.dart';
import '../widgets/update_banner.dart';
import '../widgets/sync_status_banner.dart';
import '../widgets/cover_image.dart';
import '../widgets/user_avatar.dart';
import 'search_screen.dart';

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
          int
        )>(
      selector: (_, state) => (
        state.homeWeeklyTracks,
        state.homeTopArtists,
        state.homeDiscoveryAlbums,
        state.homeNewOnServerAlbums,
        state.userName,
        state.missingTracks,
        state.avatarVersion,
      ),
      builder: (context, data, child) {
        final (
          weeklyTracks,
          topArtists,
          discoveryAlbums,
          newOnServer,
          userName,
          missingTracks,
          avatarVersion
        ) = data;
        final state = context.read<AppState>();
        return SafeArea(
          bottom: false,
          child: CustomScrollView(
            key: const Key('mobileHomeScrollView'),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
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
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: UpdateBanner()),
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
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
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
    final recentPlays = state.recentPlays; // deja limite a 6 par AppState

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

            return GestureDetector(
              onTap: () => _openRecentPlay(context, state, entry),
              child: Container(
                height: 56,
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
      child: SizedBox(
        height: 150,
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
          final liked = state.likedTracks;
          if (liked.isNotEmpty) {
            state.playTrack(liked.first, trackList: liked);
          }
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
    }
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
                subtitle: Text(
                  state.navidromeUrl ?? '',
                  style: const TextStyle(color: Colors.white54),
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
    }
  }

  BorderRadius get _shape => entry.type == RecentPlayType.artist
      ? const BorderRadius.all(Radius.circular(28))
      : const BorderRadius.horizontal(left: Radius.circular(6));

  @override
  Widget build(BuildContext context) {
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
