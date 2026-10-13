import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../navigation/overlay_navigator.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/discovered_album.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../widgets/download_button.dart';
import '../widgets/track_tile.dart';
import '../widgets/cover_image.dart';
import '../widgets/artist_options_sheet.dart';
import '../widgets/bottom_bar_reserve.dart';
import '../widgets/player/player_options_sheet.dart';
import '../features/artist/artist_model.dart';
import '../features/shared/download_waiters.dart';
import 'album_screen.dart';
import 'artist_discography_screen.dart';
import 'discovered_album_screen.dart';

class ArtistScreen extends StatefulWidget implements KeyedOverlay {
  final String artistName;

  const ArtistScreen({super.key, required this.artistName});

  /// Taper deux fois de suite sur le meme artiste n'empile pas deux pages.
  @override
  Object get overlayKey => artistName;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  // Position de defilement par artiste, conservee pour la duree de la
  // session -- restauree a la reouverture d'une page artiste deja visitee
  // au lieu de systematiquement remonter en haut (retour utilisateur).
  static final Map<String, double> _savedScrollOffsets = {};

  late final ArtistModel _model;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
        initialScrollOffset: _savedScrollOffsets[widget.artistName] ?? 0);
    _scrollController.addListener(() {
      _savedScrollOffsets[widget.artistName] = _scrollController.offset;
    });
    // Seuls 4 albums sont affiches ici (voir shownAlbumEntries) : on ne
    // verifie que les 12 premiers plutot que toute la discographie Deezer
    // (retour utilisateur : chargement inutilement lourd). La page
    // Discographie fait sa propre verification complete.
    _model = ArtistModel(
      artistName: widget.artistName,
      discovery: context.read<DiscoveryService>(),
      library: context.read<AppState>(),
      deepMatchLimit: 12,
    )..addListener(_onModelChanged);
  }

  void _onModelChanged() => setState(() {});

  @override
  void dispose() {
    _model.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    // Ne se redessine que si la bibliotheque de l'artiste change, pas a
    // chaque notification d'AppState (position de lecture...).
    return Selector<AppState, ArtistLibrary>(
      selector: (_, __) => model.local,
      builder: (context, data, child) {
        final allArtistTracks = data.tracks;
        final state = context.read<AppState>();
        final popularTracks = model.popularTracks;
        // Un maximum de 4 albums (2x2) sur la page artiste, le reste (et le
        // tracklist complet de chaque album) n'est visible que sur la page
        // "Discographie" dediee -- sinon la page artiste devenait trop
        // chargee a afficher tous les albums d'un coup (retour utilisateur).
        final shownAlbumEntries = model.albumEntries.take(4).toList();

        final artistImage = model.imageUrl;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => state.popOverlay(),
            ),
            title: Text(widget.artistName,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () => showArtistOptions(context, widget.artistName,
                    coverPath: artistImage),
              ),
            ],
          ),
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // HEADER
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _ArtistAvatar(url: artistImage),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.artistName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${allArtistTracks.length} titres locaux',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 14),
                            ),
                            if (model.discoveredAlbums.isNotEmpty)
                              Text(
                                '${model.discoveredAlbums.length} albums sur Deezer',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ACTIONS
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: model.playAll,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Lecture'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DB954),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.shuffle, color: Colors.white),
                        onPressed: () => model.playAll(shuffle: true),
                      ),
                    ],
                  ),
                ),
              ),

              // TITRES POPULAIRES (depuis Deezer)
              if (model.isLoading) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Text('Titres populaires',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _SkeletonPopularTile(index: index),
                      childCount: 5,
                    ),
                  ),
                ),
              ] else if (popularTracks.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Text('Titres populaires',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _PopularTrackTile(
                        index: index,
                        track: popularTracks[index],
                        onPlay: () => model.playPopular(popularTracks[index]),
                        downloadState: model.downloadStateOf(
                            popularTracks[index].discovered.id),
                        showDownloadButton: model.canDownload,
                        // Pas besoin de recharger les titres populaires
                        // apres coup : model.popularTracks recroise deja
                        // Deezer et la bibliotheque a chaque reconstruction.
                        onDownloadTap: () => model.downloadTrack(
                            popularTracks[index].discovered,
                            wait: waitWithProgressDialog(context)),
                      ),
                      childCount: popularTracks.length,
                    ),
                  ),
                ),
              ],

              // ALBUMS (max 4 aperçu, le reste sur la page Discographie)
              if (shownAlbumEntries.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Row(
                      children: [
                        const Text(
                          'Albums',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (model.isDeepMatching) ...[
                          const SizedBox(width: 12),
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white38,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Vérification ${model.deepMatchProgress}/${model.deepMatchTotal}',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                        ],
                        const Spacer(),
                        TextButton(
                          onPressed: () => state.pushOverlay(
                              ArtistDiscographyScreen(
                                  artistName: widget.artistName)),
                          child: const Text('Discographie',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final entry = shownAlbumEntries[index];
                        if (entry.local != null) {
                          return _LocalAlbumCard(
                            album: entry.local!,
                            state: state,
                            artistName: widget.artistName,
                            totalTrackCount: entry.knownTotalTrackCount,
                          );
                        } else {
                          return _DiscoveredAlbumCard(
                            album: entry.discovered!,
                            state: state,
                            artistName: widget.artistName,
                          );
                        }
                      },
                      childCount: shownAlbumEntries.length,
                    ),
                  ),
                ),
              ] else if (model.isLoading) ...[
                const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child:
                          CircularProgressIndicator(color: Color(0xFF1DB954)),
                    ),
                  ),
                ),
              ],

              // DANS LE NAS (titres locaux, distincts des "Titres populaires"
              // Deezer qui peuvent ne pas etre possedes -- voir DownloadStateIcon)
              if (allArtistTracks.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Text(
                      'Dans le NAS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  // Ni SliverPadding ni Padding n'acceptent de valeurs
                  // negatives (les deux s'appuient sur la meme assertion
                  // RenderPadding/RenderShiftedBox) -- la compensation du
                  // contentPadding fixe de TrackTile (16, non modifiable ici
                  // sans affecter tout le reste de l'app qui partage ce
                  // widget) se fait donc via Transform.translate, qui
                  // deplace juste le rendu sans toucher aux contraintes de
                  // layout (retour utilisateur : quelques pixels d'ecart
                  // avec "Titres populaires" plus haut).
                  padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Transform.translate(
                        offset: const Offset(8, 0),
                        child: Selector<AppState, Track?>(
                          selector: (_, s) => s.displayTrack,
                          builder: (context, currentTrack, __) => TrackTile(
                            track: allArtistTracks[index],
                            isPlaying:
                                currentTrack?.id == allArtistTracks[index].id,
                            onTap: () =>
                                model.playLocal(allArtistTracks[index]),
                            onLike: () =>
                                state.toggleLike(allArtistTracks[index].id),
                            onMore: () => showPlayerOptions(
                                context, allArtistTracks[index]),
                          ),
                        ),
                      ),
                      childCount: allArtistTracks.length,
                    ),
                  ),
                ),
              ],

              SliverToBoxAdapter(
                  child: SizedBox(height: bottomBarReserve(context))),
            ],
          ),
        );
      },
    );
  }
}

// TITRE POPULAIRE
class _PopularTrackTile extends StatelessWidget {
  final int index;
  final PopularTrack track;
  final VoidCallback onPlay;
  final DownloadUiState? downloadState;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;

  const _PopularTrackTile({
    required this.index,
    required this.track,
    required this.onPlay,
    required this.downloadState,
    required this.showDownloadButton,
    required this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAvailable = track.local != null;

    return InkWell(
      onTap: isAvailable ? onPlay : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        // Marge droite reduite (8 au lieu de 16) : rapproche les icones du
        // bord sans les coller completement, sans toucher la marge gauche
        // (pochette/texte) -- retour utilisateur.
        padding: const EdgeInsets.fromLTRB(16, 10, 0, 10),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(4),
                image: track.discovered.coverUrl != null
                    ? DecorationImage(
                        image: coverImageProvider(context,
                            path: track.discovered.coverUrl!,
                            width: 48,
                            height: 48),
                        fit: BoxFit.cover,
                        onError: (_, __) {},
                      )
                    : null,
              ),
              child: track.discovered.coverUrl == null
                  ? const Icon(Icons.music_note, color: Colors.white54)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.discovered.title,
                    style: TextStyle(
                      color: isAvailable ? Colors.white : Colors.white38,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.discovered.albumName,
                    style: TextStyle(
                      color: isAvailable ? Colors.white54 : Colors.white24,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Like et "..." en IconButton standard (48x48, pas de padding
            // custom) ; DownloadStateIcon recentre dans la meme boite 48x48
            // (voir plus bas) pour tomber au meme x que le "..." -- version
            // confirmee alignee par l'utilisateur.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isAvailable)
                  // Like puis "..." (lire ensuite, file d'attente,
                  // partager...) -- l'icone de lecture separee etait
                  // redondante avec le tap sur toute la ligne (onTap
                  // ci-dessus, deja branche sur onPlay), remplacee par le
                  // like comme sur les autres listes de titres, meme logique
                  // que DesktopArtistView (retour utilisateur).
                  IconButton(
                    icon: Icon(
                      track.local!.isLiked
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: track.local!.isLiked
                          ? const Color(0xFF1DB954)
                          : Colors.white54,
                      size: 20,
                    ),
                    onPressed: () =>
                        context.read<AppState>().toggleLike(track.local!.id),
                    splashRadius: 20,
                  )
                else
                  const IconButton(
                    icon: SizedBox.shrink(),
                    onPressed: null,
                  ),
                if (isAvailable)
                  IconButton(
                    icon: const Icon(Icons.more_vert,
                        color: Colors.white54, size: 20),
                    onPressed: () => showPlayerOptions(context, track.local!),
                    splashRadius: 20,
                  )
                else
                  // DownloadStateIcon n'a qu'un padding de 4 autour de son
                  // icone (voir download_button.dart), contre les 48x48
                  // centres par defaut d'un IconButton -- recentre dans la
                  // meme boite 48x48 pour tomber exactement au meme x que le
                  // "..." (retour utilisateur : version confirmee alignee).
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: DownloadStateIcon(
                        state: downloadState,
                        showDownloadButton: showDownloadButton,
                        onDownloadTap: onDownloadTap,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// CARTE ALBUM LOCAL
class _LocalAlbumCard extends StatelessWidget {
  final Album album;
  final AppState state;
  final String artistName;
  // Nombre de titres reel de l'album cote Deezer, quand connu -- affiche a
  // la place du nombre de titres deja telecharges pour un album seulement
  // partiellement possede.
  final int? totalTrackCount;

  const _LocalAlbumCard({
    required this.album,
    required this.state,
    required this.artistName,
    this.totalTrackCount,
  });

  @override
  Widget build(BuildContext context) {
    // album.trackIds est deja le decompte exact de cet album precis (voir
    // MusicService.rebuildAlbums) -- pas besoin de re-derouler par titre,
    // qui pouvait compter les titres d'un autre album partageant le meme
    // nom.
    final trackCount = totalTrackCount ?? album.trackIds.length;

    final cover = Expanded(child: _AlbumCover(coverPath: album.coverPath));

    final card = GestureDetector(
      onTap: () => state
          .pushOverlay(AlbumScreen(album: album, filterArtist: artistName)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          cover,
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
            '$trackCount titres',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );

    return card;
  }
}

// CARTE ALBUM DECOUVERT (GRISE)
class _DiscoveredAlbumCard extends StatelessWidget {
  final DiscoveredAlbum album;
  final AppState state;
  final String artistName;

  const _DiscoveredAlbumCard({
    required this.album,
    required this.state,
    required this.artistName,
  });

  @override
  Widget build(BuildContext context) {
    const coverSide = 150.0;
    final coverBox = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        image: album.coverUrl != null
            ? DecorationImage(
                image: coverImageProvider(context,
                    path: album.coverUrl!, width: coverSide, height: coverSide),
                fit: BoxFit.cover,
                onError: (_, __) {},
              )
            : null,
      ),
      child: album.coverUrl == null
          ? const Center(
              child: Icon(Icons.album, color: Colors.white54, size: 48))
          : null,
    );
    final cover = Expanded(child: coverBox);

    final card = GestureDetector(
      onTap: () => state.pushOverlay(
          DiscoveredAlbumScreen(album: album, filterArtist: artistName)),
      child: Opacity(
        opacity: 0.45,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            cover,
            const SizedBox(height: 8),
            Text(
              album.title,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              album.releaseDate ?? '',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, color: Colors.white24, size: 10),
                  SizedBox(width: 4),
                  Text('Non disponible',
                      style: TextStyle(color: Colors.white24, fontSize: 9)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return card;
  }
}

// WIDGETS REUTILISABLES

class _ArtistAvatar extends StatelessWidget {
  final String? url;
  const _ArtistAvatar({this.url});

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;

    if (imageUrl != null) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          image: DecorationImage(
            image: coverImageProvider(context,
                path: imageUrl, width: 80, height: 80),
            fit: BoxFit.cover,
            onError: (_, __) {},
          ),
        ),
      );
    }
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF3E3E3E),
        borderRadius: BorderRadius.circular(40),
      ),
      child: const Icon(Icons.person, color: Colors.white54, size: 40),
    );
  }
}

class _AlbumCover extends StatelessWidget {
  final String? coverPath;
  const _AlbumCover({this.coverPath});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;

    final exists = path != null && path.startsWith('http')
        ? true
        : context.read<AppState>().coverExists(path);

    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
          image: exists && path != null
              ? DecorationImage(
                  image: coverImageProvider(context,
                      path: path,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight),
                  fit: BoxFit.cover,
                  onError: (_, __) {},
                )
              : null,
        ),
        child: exists != true
            ? const Center(
                child: Icon(Icons.album, color: Colors.white54, size: 48),
              )
            : null,
      );
    });
  }
}

class _SkeletonPopularTile extends StatelessWidget {
  final int index;
  const _SkeletonPopularTile({required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${index + 1}',
              style: const TextStyle(color: Colors.white24, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 120,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
