import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/discovered_album.dart';
import '../models/discovered_artist.dart';
import '../models/discovered_track.dart';
import '../models/search_history_item.dart';
import '../models/track.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../services/matching_service.dart';
import '../services/search_history_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/download_button.dart';
import '../widgets/download_progress_dialog.dart';
import 'desktop_horizontal_shelf.dart';
import 'glass.dart';
import '../widgets/smooth_scroll.dart';

/// Recherche desktop : titres locaux + artistes/albums Deezer, avec
/// historique des consultations -- equivalent desktop de SearchScreen
/// (mobile), mise en etageres plutot qu'en onglets vu la largeur
/// disponible.
class DesktopSearchView extends StatefulWidget {
  final ValueChanged<String> onOpenArtist;
  final void Function(Album album, {String? filterArtist}) onOpenAlbum;
  final void Function(
      {DiscoveredAlbum? album,
      int? albumId,
      String? filterArtist}) onOpenDiscoveredAlbum;

  const DesktopSearchView({
    super.key,
    required this.onOpenArtist,
    required this.onOpenAlbum,
    required this.onOpenDiscoveredAlbum,
  });

  @override
  State<DesktopSearchView> createState() => _DesktopSearchViewState();
}

class _DesktopSearchViewState extends State<DesktopSearchView> {
  final _controller = TextEditingController();
  final _discovery = DiscoveryService();
  final _historyService = SearchHistoryService();
  final _downloadWorker = DownloadWorkerService();
  final _scrollController = SmoothScrollController();

  Timer? _debounce;
  bool _isLoading = false;
  String _query = '';

  List<_SearchTrack> _tracks = [];
  List<DiscoveredArtist> _artists = [];
  List<DiscoveredAlbum> _albums = [];
  List<SearchHistoryItem> _history = [];
  final Map<int, DownloadUiState> _downloadStates = {};

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _historyService.setCurrentUser(state.currentUserId);
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    await _historyService.ensureLoaded();
    if (mounted) setState(() => _history = _historyService.history);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _query = '';
        _tracks = [];
        _artists = [];
        _albums = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Track? _findLocalTrack(DiscoveredTrack dt, List<Track> candidates) {
    for (final t in candidates) {
      if (MatchingService.artistsMatch(t.artist, dt.artistName) &&
          MatchingService.titlesMatch(t.title, dt.title)) {
        return t;
      }
    }
    return null;
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _query = query;
    });

    final state = context.read<AppState>();
    final results = await Future.wait([
      _discovery.searchArtists(query, limit: 10),
      // Pas de tri par popularite d'artiste ici (contrairement a une
      // premiere version) : ca faisait sortir en premier les albums de
      // l'artiste Deezer le plus connu parmi les resultats plutot que les
      // albums les plus pertinents pour la recherche tapee -- l'app mobile
      // (SearchScreen) garde l'ordre de pertinence renvoye par Deezer et
      // fonctionne bien (retour utilisateur), on fait pareil ici.
      _discovery.searchAlbums(query, limit: 12),
      _discovery.searchTracks(query, limit: 15),
    ]);

    if (!mounted) return;
    final artists = results[0] as List<DiscoveredArtist>;
    final albums = results[1] as List<DiscoveredAlbum>;
    final discoveredTracks = results[2] as List<DiscoveredTrack>;
    // Titres trouves via l'API Deezer (pas uniquement ceux deja sur le NAS,
    // retour utilisateur) : chaque resultat garde un lien vers son titre
    // local s'il existe deja (pour la lecture directe), sinon reste
    // telechargeable comme les autres listes de titres decouverts de l'app.
    final localTracks = state.allTracks;
    final tracks = [
      for (final dt in discoveredTracks)
        _SearchTrack(discovered: dt, local: _findLocalTrack(dt, localTracks)),
    ];

    setState(() {
      _tracks = tracks;
      _artists = artists;
      _albums = albums;
      _isLoading = false;
    });
  }

  void _openArtistResult(DiscoveredArtist artist) {
    _historyService.addArtist(artist.name, artist.id.toString(),
        query: _query, imageUrl: artist.pictureUrl);
    widget.onOpenArtist(artist.name);
  }

  void _openAlbumResult(DiscoveredAlbum album) {
    _historyService.addAlbum(album.title, album.id.toString(), album.artistName,
        query: _query, imageUrl: album.coverUrl);
    final state = context.read<AppState>();
    Album? localAlbum;
    try {
      localAlbum = state.albums.firstWhere(
        (a) => a.title.toLowerCase().trim() == album.title.toLowerCase().trim(),
      );
    } catch (_) {
      localAlbum = null;
    }
    if (localAlbum != null) {
      widget.onOpenAlbum(localAlbum);
    } else {
      widget.onOpenDiscoveredAlbum(album: album);
    }
  }

  Future<void> _playLocalTrack(Track track) async {
    await _historyService.addTrack(
      track.title,
      track.id,
      track.artist,
      query: _query,
      imageUrl:
          track.coverPath?.startsWith('http') == true ? track.coverPath : null,
    );
    if (!mounted) return;
    final playable = [
      for (final t in _tracks)
        if (t.local != null) t.local!
    ];
    context.read<AppState>().playTrack(track, trackList: playable);
  }

  /// Demande le telechargement automatique d'un titre trouve via Deezer mais
  /// pas encore sur le NAS -- meme logique que DesktopArtistView/AlbumScreen
  /// (DownloadWorkerService), jusqu'ici jamais branchee sur cette page
  /// puisque la recherche ne montrait que des titres locaux.
  Future<void> _downloadTrack(DiscoveredTrack track) async {
    setState(() => _downloadStates[track.id] = DownloadUiState.downloading);

    final jobId = await _downloadWorker.requestDownload(
      artist: track.artistName,
      title: track.title,
      album: track.albumName == 'Inconnu' ? null : track.albumName,
    );
    if (jobId == null) {
      if (mounted) {
        setState(() => _downloadStates[track.id] = DownloadUiState.failed);
      }
      return;
    }

    if (!mounted) return;
    final status = await showDownloadProgressDialog(context,
        worker: _downloadWorker, jobId: jobId);
    if (!mounted) return;

    if (status.state == DownloadJobState.done) {
      await context
          .read<AppState>()
          .handleTrackDownloaded(track.artistName, track.title);
      if (mounted) {
        setState(() {
          _downloadStates.remove(track.id);
          final i = _tracks.indexWhere((t) => t.discovered.id == track.id);
          if (i != -1) {
            _tracks[i] = _SearchTrack(
              discovered: track,
              local: _findLocalTrack(track, context.read<AppState>().allTracks),
            );
          }
        });
      }
    } else {
      setState(() => _downloadStates[track.id] = DownloadUiState.failed);
    }
  }

  void _onHistoryTap(SearchHistoryItem item) {
    switch (item.type) {
      case 'artist':
        if (item.name != null) widget.onOpenArtist(item.name!);
        break;
      case 'album':
        if (item.id != null) {
          widget.onOpenDiscoveredAlbum(albumId: int.tryParse(item.id!));
        }
        break;
      case 'track':
        if (item.id != null) {
          final state = context.read<AppState>();
          final matches =
              state.allTracks.where((t) => t.id == item.id).toList();
          if (matches.isNotEmpty) state.playTrack(matches.first);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // top: titleBarHeight (pas topInset) -- l'onglet Recherche masque la
    // barre de recherche persistante du shell (voir _TopBar.showSearchBar
    // dans desktop_app_shell.dart), donc plus besoin de lui reserver de
    // place ici : ce champ de recherche demarre juste sous la barre de
    // titre plutot que sous un grand vide (retour utilisateur).
    return Padding(
      padding: const EdgeInsets.only(top: DesktopGlass.titleBarHeight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Copie structurelle exacte du pill de recherche de la home
          // (_TopBar dans desktop_app_shell.dart) -- Align+ConstrainedBox(420)
          // +GlassPanel+SizedBox(36)+Row[Icon, SizedBox(8), texte], dans le
          // meme ordre, avec les memes valeurs -- seul le texte statique y
          // est remplace par un TextField fonctionnel (retour utilisateur :
          // "meme en copiant le style ca ne devrait plus changer si c'est
          // vraiment le meme rendu").
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: GlassPanel(
                borderRadius: BorderRadius.circular(20),
                blurSigma: 0,
                tint: Colors.white.withOpacity(0.06),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SizedBox(
                  height: 36,
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.white54, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Titres, artistes, albums...',
                            hintStyle:
                                TextStyle(color: Colors.white38, fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: _onChanged,
                          onSubmitted: _search,
                        ),
                      ),
                      if (_controller.text.isNotEmpty)
                        GlassIconButton(
                          icon: Icons.clear,
                          size: 16,
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_isLoading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(
                color: DesktopGlass.accent,
                backgroundColor: Colors.transparent),
          ],
          const SizedBox(height: 20),
          Expanded(
            child: _query.isEmpty ? _buildHistory() : _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return const Center(
        child: Text('Recherchez un artiste, un album ou un titre',
            style: TextStyle(color: Colors.white38)),
      );
    }
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: DesktopGlass.playerBarReserve),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Récemment consultés',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            TextButton(
              onPressed: () async {
                await _historyService.clear();
                if (mounted) setState(() => _history = []);
              },
              child: const Text('Effacer',
                  style: TextStyle(color: DesktopGlass.accent)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final item in _history)
          _HistoryRow(
            item: item,
            onTap: () => _onHistoryTap(item),
            onRemove: () async {
              await _historyService.remove(item);
              if (mounted) setState(() => _history = _historyService.history);
            },
          ),
      ],
    );
  }

  Widget _buildResults() {
    final hasAnything =
        _artists.isNotEmpty || _albums.isNotEmpty || _tracks.isNotEmpty;
    if (!hasAnything && !_isLoading) {
      return const Center(
        child: Text('Aucun résultat', style: TextStyle(color: Colors.white38)),
      );
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: DesktopGlass.playerBarReserve),
      children: [
        if (_artists.isNotEmpty) ...[
          _sectionTitle('Artistes'),
          DesktopHorizontalShelf(
            height: 128,
            itemCount: _artists.length,
            itemBuilder: (context, i) {
              final artist = _artists[i];
              return Padding(
                padding: const EdgeInsets.only(right: 20),
                child: SizedBox(
                  width: 100,
                  child: DesktopHoverable(
                    onTap: () => _openArtistResult(artist),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 44,
                          backgroundColor: const Color(0xFF3E3E3E),
                          backgroundImage: artist.pictureUrl != null
                              ? coverImageProvider(context,
                                  path: artist.pictureUrl!,
                                  width: 88,
                                  height: 88)
                              : null,
                          onBackgroundImageError:
                              artist.pictureUrl != null ? (_, __) {} : null,
                          child: artist.pictureUrl == null
                              ? const Icon(Icons.person,
                                  color: Colors.white54, size: 32)
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(artist.name,
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
          ),
        ],
        if (_albums.isNotEmpty) ...[
          _sectionTitle('Albums'),
          // Une seule rangee qui defile horizontalement, comme la rangee
          // Artistes juste au-dessus -- retour utilisateur : ca permet de
          // parcourir les resultats plus vite qu'une grille sur plusieurs
          // lignes.
          DesktopHorizontalShelf(
            height: 210,
            itemCount: _albums.length,
            itemBuilder: (context, i) {
              final album = _albums[i];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 166,
                  child: _AlbumResultCard(
                      album: album, onTap: () => _openAlbumResult(album)),
                ),
              );
            },
          ),
        ],
        if (_tracks.isNotEmpty) ...[
          _sectionTitle('Titres (${_tracks.length})'),
          Selector<AppState, Track?>(
            selector: (_, s) => s.displayTrack,
            builder: (context, currentTrack, __) {
              return Column(
                children: [
                  for (final t in _tracks)
                    _SearchTrackRow(
                      track: t,
                      isPlaying:
                          t.local != null && currentTrack?.id == t.local!.id,
                      onTap: t.local != null
                          ? () => _playLocalTrack(t.local!)
                          : null,
                      onLike: t.local != null
                          ? () =>
                              context.read<AppState>().toggleLike(t.local!.id)
                          : null,
                      downloadState: _downloadStates[t.discovered.id],
                      showDownloadButton: _downloadWorker.isConfigured,
                      onDownloadTap: () => _downloadTrack(t.discovered),
                    ),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
      );
}

class _AlbumResultCard extends StatelessWidget {
  final DiscoveredAlbum album;
  final VoidCallback onTap;

  const _AlbumResultCard({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DesktopHoverable(
      onTap: onTap,
      // Meme espace autour de la cover que les tuiles de la home (voir
      // DesktopHoverable dans _trackShelf/_albumShelf) : la surbrillance
      // deborde legerement de la cover au lieu de la suivre au pixel pres.
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Opacity(
          opacity: album.isInLibrary ? 0.5 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
                    image: album.coverUrl != null
                        ? DecorationImage(
                            image: coverImageProvider(context,
                                path: album.coverUrl!, width: 180, height: 180),
                            fit: BoxFit.cover,
                            onError: (_, __) {})
                        : null,
                  ),
                  child: album.coverUrl == null
                      ? const Center(
                          child: Icon(Icons.album,
                              color: Colors.white54, size: 40))
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(album.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(album.artistName,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (album.isInLibrary)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: DesktopGlass.accent, size: 12),
                      SizedBox(width: 4),
                      Text('Dans la bibliothèque',
                          style: TextStyle(
                              color: DesktopGlass.accent, fontSize: 10)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un resultat de la section "Titres" : toujours issu de la recherche
/// Deezer (retour utilisateur -- avant, cette section ne montrait que les
/// titres deja sur le NAS), avec un lien vers le titre local correspondant
/// quand il existe deja, pour la lecture directe.
class _SearchTrack {
  final DiscoveredTrack discovered;
  final Track? local;
  const _SearchTrack({required this.discovered, this.local});
}

/// Ligne d'un resultat de la section "Titres" -- meme habillage que
/// _PopularTrackRow (DesktopArtistView) : cover, titre/artiste, puis
/// like+menu si le titre est deja sur le NAS, sinon un bouton de
/// telechargement (voir DownloadStateIcon) plutot qu'une ligne inerte, comme
/// partout ailleurs ou l'app montre un titre pas encore possede.
class _SearchTrackRow extends StatelessWidget {
  final _SearchTrack track;
  final bool isPlaying;
  final VoidCallback? onTap;
  final VoidCallback? onLike;
  final DownloadUiState? downloadState;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;

  const _SearchTrackRow({
    required this.track,
    required this.isPlaying,
    required this.onTap,
    required this.onLike,
    required this.downloadState,
    required this.showDownloadButton,
    required this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    final discovered = track.discovered;
    final isAvailable = track.local != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(6),
                image: discovered.coverUrl != null
                    ? DecorationImage(
                        image: coverImageProvider(context,
                            path: discovered.coverUrl!, width: 44, height: 44),
                        fit: BoxFit.cover,
                        onError: (_, __) {})
                    : null,
              ),
              child: discovered.coverUrl == null
                  ? const Icon(Icons.music_note,
                      color: Colors.white54, size: 18)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    discovered.title,
                    style: TextStyle(
                      color: isPlaying
                          ? DesktopGlass.accent
                          : isAvailable
                              ? Colors.white
                              : Colors.white38,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    discovered.artistName,
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
            if (isAvailable && onLike != null)
              GlassIconButton(
                icon: track.local!.isLiked
                    ? Icons.favorite
                    : Icons.favorite_border,
                color:
                    track.local!.isLiked ? DesktopGlass.accent : Colors.white54,
                size: 18,
                onPressed: onLike!,
              )
            else
              DownloadStateIcon(
                state: downloadState,
                showDownloadButton: showDownloadButton,
                onDownloadTap: onDownloadTap,
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatefulWidget {
  final SearchHistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  const _HistoryRow(
      {required this.item, required this.onTap, required this.onRemove});

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _hover = false;

  /// Prefixe le type de resultat ("Titre"/"Album"/"Artiste") devant l'ancien
  /// sous-titre (juste le nom de l'artiste pour titre/album, rien pour
  /// artiste) -- sans ça rien ne distinguait un titre d'un album au premier
  /// coup d'oeil dans "Recemment consultes" (retour utilisateur).
  String _typeLabel(String type) => switch (type) {
        'artist' => 'Artiste',
        'album' => 'Album',
        _ => 'Titre',
      };

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isArtist = item.type == 'artist';
    final label = _typeLabel(item.type);
    final subtitleLine =
        item.subtitle == null ? label : '$label · ${item.subtitle}';

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hover ? Colors.white.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF3E3E3E),
                  borderRadius: BorderRadius.circular(isArtist ? 22 : 6),
                  image: item.imageUrl != null
                      ? DecorationImage(
                          image: coverImageProvider(context,
                              path: item.imageUrl!, width: 44, height: 44),
                          fit: BoxFit.cover,
                          onError: (_, __) {})
                      : null,
                ),
                child: item.imageUrl == null
                    ? Icon(
                        isArtist
                            ? Icons.person
                            : item.type == 'album'
                                ? Icons.album
                                : Icons.music_note,
                        color: Colors.white54,
                        size: 18,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.displayName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(subtitleLine,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              GlassIconButton(
                icon: Icons.close,
                size: 16,
                onPressed: widget.onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
