import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/discovered_album.dart';
import '../models/discovered_artist.dart';
import '../models/search_history_item.dart';
import '../models/track.dart';
import '../services/discovery_service.dart';
import '../services/search_history_service.dart';
import '../widgets/cover_image.dart';
import 'desktop_horizontal_shelf.dart';
import 'desktop_track_row.dart';
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
  final _scrollController = SmoothScrollController();

  Timer? _debounce;
  bool _isLoading = false;
  String _query = '';

  List<Track> _localTracks = [];
  List<DiscoveredArtist> _artists = [];
  List<DiscoveredAlbum> _albums = [];
  List<SearchHistoryItem> _history = [];

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
        _localTracks = [];
        _artists = [];
        _albums = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _query = query;
    });

    final state = context.read<AppState>();
    final local = state.musicService.searchTracks(query);
    final results = await Future.wait([
      _discovery.searchArtists(query, limit: 10),
      _discovery.searchAlbums(query, limit: 12),
    ]);

    if (!mounted) return;
    setState(() {
      _localTracks = local;
      _artists = results[0] as List<DiscoveredArtist>;
      _albums = results[1] as List<DiscoveredAlbum>;
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
    context.read<AppState>().playTrack(track, trackList: _localTracks);
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
    // top: DesktopGlass.topInset -- la TopBar du shell (avatar/spinner sur
    // cet onglet) flotte au-dessus du contenu, cette page a son propre
    // champ de recherche fixe qui doit donc demarrer en dessous plutot que
    // se superposer avec elle.
    return Padding(
      padding: const EdgeInsets.only(top: DesktopGlass.topInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassPanel(
            borderRadius: BorderRadius.circular(24),
            blurSigma: 0,
            tint: Colors.white.withOpacity(0.06),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 46,
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.white54, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Titres, artistes, albums...',
                        hintStyle: TextStyle(color: Colors.white38),
                        border: InputBorder.none,
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
        _artists.isNotEmpty || _albums.isNotEmpty || _localTracks.isNotEmpty;
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
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              childAspectRatio: 0.72,
              crossAxisSpacing: 14,
              mainAxisSpacing: 18,
            ),
            itemCount: _albums.length,
            itemBuilder: (context, i) {
              final album = _albums[i];
              return _AlbumResultCard(
                  album: album, onTap: () => _openAlbumResult(album));
            },
          ),
        ],
        if (_localTracks.isNotEmpty) ...[
          _sectionTitle('Titres (${_localTracks.length})'),
          Selector<AppState, Track?>(
            selector: (_, s) => s.currentTrack,
            builder: (context, currentTrack, __) {
              return Column(
                children: [
                  for (final track in _localTracks)
                    DesktopTrackRow(
                      track: track,
                      isPlaying: currentTrack?.id == track.id,
                      onTap: () => _playLocalTrack(track),
                      onLike: () =>
                          context.read<AppState>().toggleLike(track.id),
                      onMore: () {},
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

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isArtist = item.type == 'artist';

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
                    if (item.subtitle != null)
                      Text(item.subtitle!,
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
