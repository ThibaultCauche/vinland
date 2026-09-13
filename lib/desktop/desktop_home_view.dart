import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../models/recent_play.dart';
import '../models/track.dart';
import '../widgets/smooth_scroll.dart';
import '../widgets/sync_status_banner.dart';
import '../widgets/update_banner.dart';
import '../widgets/cover_image.dart';
import 'desktop_horizontal_shelf.dart';
import 'glass.dart';

/// Accueil desktop : shelves horizontales dans des cartes en verre, comme
/// la home mobile mais redimensionnee pour un grand ecran.
class DesktopHomeView extends StatefulWidget {
  final ValueChanged<Album> onOpenAlbum;
  final ValueChanged<Track> onPlayTrackShelf;
  final ValueChanged<String> onOpenArtist;
  final VoidCallback onOpenLikedSongs;
  final ValueChanged<Playlist> onOpenPlaylist;

  const DesktopHomeView({
    super.key,
    required this.onOpenAlbum,
    required this.onPlayTrackShelf,
    required this.onOpenArtist,
    required this.onOpenLikedSongs,
    required this.onOpenPlaylist,
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
        state.recentPlays,
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
            const UpdateBanner(),
            // Pendant une synchro normale, seul le petit cercle vert du
            // TopBar (a cote de l'avatar) suffit -- ce bandeau ne reapparait
            // que pour l'etat d'erreur (NAS injoignable), qui merite d'etre
            // vu et a un bouton "Reessayer".
            if (!isSyncing) const SyncStatusBanner(),
            if (recentPlays.isNotEmpty) ...[
              _recentPlayGrid(context, state, recentPlays),
              const SizedBox(height: 8),
            ],
            _sectionTitle('Écoutés cette semaine'),
            _trackShelf(context, weeklyTracks),
            _sectionTitle('Artistes du moment'),
            _artistShelf(context, topArtists),
            _sectionTitle('Découverte'),
            _albumShelf(context, discoveryAlbums),
            _sectionTitle('Nouveautés du NAS'),
            _albumShelf(context, newOnServer),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 12),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
      );

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
                    _ShelfCover(coverPath: track.coverPath, size: 150),
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
                    _ShelfCover(coverPath: album.coverPath, size: 150),
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
                children: [
                  ClipOval(
                    child: _ShelfCover(coverPath: coverPath, size: 96),
                  ),
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

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
          ),
          child: Row(
            children: [
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
    }
  }

  BorderRadius get _shape => entry.type == RecentPlayType.artist
      ? const BorderRadius.all(Radius.circular(48))
      : const BorderRadius.horizontal(
          left: Radius.circular(DesktopGlass.radiusSm));

  @override
  Widget build(BuildContext context) {
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

class _ShelfCover extends StatelessWidget {
  final String? coverPath;
  final double size;
  const _ShelfCover({required this.coverPath, required this.size});

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
