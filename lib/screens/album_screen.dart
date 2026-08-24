import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/track.dart';
import '../models/discovered_track.dart';
import '../models/discovered_album.dart';
import '../services/discovery_service.dart';
import 'artist_screen.dart';

class AlbumScreen extends StatefulWidget {
  final Album album;
  final String? filterArtist;
  const AlbumScreen({super.key, required this.album, this.filterArtist});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  Color? _dominantColor;
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;
  final _discovery = DiscoveryService();
  List<DiscoveredTrack> _discoveredTracks = [];
  bool _loadingDeezer = false;

  @override
  void initState() {
    super.initState();
    _extractColor();
    _loadDeezerTracks();
    _scrollController.addListener(() {
      if (mounted) setState(() => _scrollOffset = _scrollController.offset);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _extractColor() async {
    final path = widget.album.coverPath;
    if (path == null) return;
    try {
      final bytes = await File(path).readAsBytes();
      final color = await compute(_dominantColorFromBytes, bytes);
      if (mounted) setState(() => _dominantColor = color);
    } catch (_) {}
  }

  static Color? _dominantColorFromBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final w = decoded.width;
    final h = decoded.height;
    final samples = [
      decoded.getPixel(w ~/ 2, h ~/ 2),
      decoded.getPixel(w ~/ 4, h ~/ 4),
      decoded.getPixel(w * 3 ~/ 4, h ~/ 4),
      decoded.getPixel(w ~/ 4, h * 3 ~/ 4),
      decoded.getPixel(w * 3 ~/ 4, h * 3 ~/ 4),
    ];
    int r = 0, g = 0, b = 0;
    for (final p in samples) {
      final pixel = p as dynamic;
      r += (pixel.r as num).round();
      g += (pixel.g as num).round();
      b += (pixel.b as num).round();
    }
    return Color.fromRGBO(
      r ~/ samples.length,
      g ~/ samples.length,
      b ~/ samples.length,
      1,
    );
  }

  Future<void> _loadDeezerTracks() async {
    if (mounted) setState(() => _loadingDeezer = true);
    try {
      final albums =
          await _discovery.searchAlbums(widget.album.title, limit: 10);
      DiscoveredAlbum? match;
      for (final a in albums) {
        if (_normalize(a.title) == _normalize(widget.album.title)) {
          match = a;
          break;
        }
      }
      if (match != null) {
        final tracks = await _discovery.getAlbumTracks(match.id);
        if (mounted) setState(() => _discoveredTracks = tracks);
      }
    } catch (e) {
      print('Deezer album tracks error: $e');
    }
    if (mounted) setState(() => _loadingDeezer = false);
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<_AlbumListItem> _buildTrackList(List<Track> localTracks) {
    final items = <_AlbumListItem>[];
    for (final t in localTracks) {
      items.add(_AlbumListItem(localTrack: t));
    }
    for (final dt in _discoveredTracks) {
      final isDup =
          localTracks.any((t) => _normalize(t.title) == _normalize(dt.title));
      if (!isDup) {
        items.add(_AlbumListItem(discoveredTrack: dt));
      }
    }
    // Garder l'ordre de l'album Deezer si possible
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    var albumTracks = appState.allTracks
        .where((t) => _normalize(t.album) == _normalize(widget.album.title))
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    if (widget.filterArtist != null) {
      bool artistMatch(String? artistField) {
        if (artistField == null) return false;
        final search = widget.filterArtist!.toLowerCase();
        final field = artistField.toLowerCase();
        if (field == search) return true;
        if (field.contains(search)) return true;
        return field.split(RegExp(r'[/&,]')).any((p) => p.trim() == search);
      }

      albumTracks = albumTracks.where((t) => artistMatch(t.artist)).toList();
    }

    final items = _buildTrackList(albumTracks);

    final topColor = _dominantColor != null
        ? Color.lerp(_dominantColor, Colors.black, 0.25)!
        : const Color(0xFF121212);
    final appBarColor = _dominantColor != null
        ? Color.lerp(_dominantColor, Colors.black, 0.35)!
        : const Color(0xFF121212);

    final appBarOpacity = ((_scrollOffset - 320) / 80).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [topColor, const Color(0xFF121212)],
            stops: const [0.0, 0.45],
          ),
        ),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: appBarOpacity == 0
                  ? Colors.transparent
                  : appBarColor.withOpacity(appBarOpacity),
              elevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              forceElevated: false,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => appState.popOverlay(),
              ),
              title: Opacity(
                opacity: appBarOpacity,
                child: Text(
                  widget.album.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildHeader(albumTracks, appState),
            ),
            SliverToBoxAdapter(
              child: _buildActionBar(albumTracks, appState),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = items[index];
                    if (item.localTrack != null) {
                      final track = item.localTrack!;
                      return _AlbumTrackTile(
                        index: index,
                        track: track,
                        onTap: () => appState.playTrack(
                          track,
                          trackList: albumTracks,
                        ),
                        onLike: () => appState.toggleLike(track.id),
                        onMore: () => _showTrackOptions(context, track),
                      );
                    } else {
                      return _DiscoveredTrackTile(
                        index: index,
                        track: item.discoveredTrack!,
                      );
                    }
                  },
                  childCount: items.length,
                ),
              ),
            ),
            if (_loadingDeezer)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF1DB954),
                      ),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 220)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(List<Track> tracks, AppState state) {
    final coverPath = widget.album.coverPath;
    final exists = state.coverExists(coverPath);
    final screenWidth = MediaQuery.of(context).size.width;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: screenWidth * 0.60,
              height: screenWidth * 0.60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
                image: exists && coverPath != null
                    ? DecorationImage(
                        image: coverPath.startsWith('http')
                            ? NetworkImage(coverPath) as ImageProvider
                            : FileImage(File(coverPath)),
                        fit: BoxFit.cover,
                      )
                    : null,
                color: const Color(0xFF2A2A2A),
              ),
              child: !exists || coverPath == null
                  ? const Icon(Icons.album, color: Colors.white54, size: 64)
                  : null,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            widget.album.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              _showArtistPicker(context, widget.album.artist);
            },
            child: Row(
              children: [
                _SmallAvatar(coverPath: widget.album.coverPath),
                const SizedBox(width: 8),
                Text(
                  widget.album.artist,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Album • ${tracks.length} titres',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(List<Track> tracks, AppState state) {
    final isLiked = widget.album.isSaved;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 16, 16),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              color: isLiked ? const Color(0xFF1DB954) : Colors.white54,
            ),
            onPressed: () => state.toggleLikeAlbum(widget.album.id),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.white54),
            onPressed: () {
              if (tracks.isNotEmpty) {
                _showAddToPlaylistDialog(context, tracks.first);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.white54),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white54),
            onPressed: () => _showAlbumOptions(context),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.shuffle, color: Colors.white54, size: 26),
            onPressed: () {
              if (tracks.isNotEmpty) {
                final shuffled = List<Track>.of(tracks)..shuffle();
                state.playTrack(shuffled.first, trackList: shuffled);
              }
            },
          ),
          const SizedBox(width: 4),
          _PlayPauseButton(albumTracks: tracks),
        ],
      ),
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, Track track) {
    final state = context.read<AppState>();
    final playlists = state.playlists;

    if (playlists.isEmpty) {
      _showSnack("Aucune playlist. Creez-en une d'abord.");
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Ajouter a une playlist',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: playlists.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(playlists[i].name,
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                state.addToPlaylist(playlists[i].id, track.id);
                Navigator.pop(ctx);
                _showSnack('Ajoute a ${playlists[i].name}');
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _showTrackOptions(BuildContext context, Track track) {
    final state = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BottomSheetHeader(
              coverPath: track.coverPath,
              title: track.title,
              subtitle: track.artist,
            ),
            const Divider(color: Color(0xFF2A2A2A), height: 1),
            _SheetTile(
              icon: Icons.add_circle_outline,
              label: 'Ajouter a la playlist',
              onTap: () {
                Navigator.pop(ctx);
                _showAddToPlaylistDialog(context, track);
              },
            ),
            _SheetTile(
              icon: Icons.playlist_add,
              label: "Ajouter a la file d'attente",
              onTap: () {
                Navigator.pop(ctx);
                _showSnack("Ajoute a la file d'attente");
              },
            ),
            _SheetTile(
              icon: Icons.album_outlined,
              label: "Acceder a l'album",
              onTap: () => Navigator.pop(ctx),
            ),
            _SheetTile(
              icon: Icons.person_outline,
              label: "Acceder a l'artiste",
              onTap: () {
                Navigator.pop(ctx);
                _showArtistPicker(context, track.artist);
              },
            ),
            _SheetTile(
              icon: track.isLiked ? Icons.favorite : Icons.favorite_border,
              label: track.isLiked
                  ? 'Retirer des titres likes'
                  : 'Ajouter aux titres likes',
              iconColor: track.isLiked ? const Color(0xFF1DB954) : Colors.white,
              onTap: () {
                Navigator.pop(ctx);
                state.toggleLike(track.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAlbumOptions(BuildContext context) {
    final state = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BottomSheetHeader(
              coverPath: widget.album.coverPath,
              title: widget.album.title,
              subtitle: widget.album.artist,
            ),
            const Divider(color: Color(0xFF2A2A2A), height: 1),
            _SheetTile(
              icon:
                  widget.album.isSaved ? Icons.favorite : Icons.favorite_border,
              label: widget.album.isSaved
                  ? 'Retirer des albums likes'
                  : 'Ajouter aux albums likes',
              onTap: () {
                Navigator.pop(ctx);
                state.toggleLikeAlbum(widget.album.id);
              },
            ),
            _SheetTile(
              icon: Icons.person_outline,
              label: "Acceder a l'artiste",
              onTap: () {
                Navigator.pop(ctx);
                _showArtistPicker(context, widget.album.artist);
              },
            ),
            _SheetTile(
              icon: Icons.playlist_add,
              label: "Ajouter a la file d'attente",
              onTap: () {
                Navigator.pop(ctx);
                _showSnack("Ajoute a la file d'attente");
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showArtistPicker(BuildContext context, String artistsField) {
    final artists = artistsField
        .split(RegExp(r'[/&,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (artists.length <= 1) {
      context
          .read<AppState>()
          .pushOverlay(ArtistScreen(artistName: artistsField));
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Selectionner un artiste',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(color: Color(0xFF2A2A2A), height: 1),
            ...artists.map((artist) => ListTile(
                  leading: const Icon(Icons.person, color: Colors.white),
                  title:
                      Text(artist, style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx);
                    context
                        .read<AppState>()
                        .pushOverlay(ArtistScreen(artistName: artist));
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF2A2A2A),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _AlbumListItem {
  final Track? localTrack;
  final DiscoveredTrack? discoveredTrack;
  const _AlbumListItem({this.localTrack, this.discoveredTrack});
}

class _SmallAvatar extends StatelessWidget {
  final String? coverPath;
  const _SmallAvatar({this.coverPath});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final exists = context.read<AppState>().coverExists(coverPath);
    if (exists && path != null) {
      return CircleAvatar(
        radius: 12,
        backgroundImage: path.startsWith('http')
            ? NetworkImage(path) as ImageProvider
            : FileImage(File(path)),
      );
    }
    return const CircleAvatar(
      radius: 12,
      backgroundColor: Color(0xFF3E3E3E),
      child: Icon(Icons.person, color: Colors.white54, size: 12),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final List<Track> albumTracks;
  const _PlayPauseButton({required this.albumTracks});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (bool, bool)>(
      selector: (_, state) {
        final isThisAlbum = state.currentTrack != null &&
            albumTracks.any((t) => t.id == state.currentTrack!.id);
        return (isThisAlbum, state.isPlaying);
      },
      builder: (context, data, _) {
        final (isThisAlbum, isPlaying) = data;
        final isPlayingThisAlbum = isThisAlbum && isPlaying;

        return GestureDetector(
          onTap: () {
            final state = context.read<AppState>();
            if (isPlayingThisAlbum) {
              state.togglePlayPause();
            } else if (albumTracks.isNotEmpty) {
              state.playTrack(albumTracks.first, trackList: albumTracks);
            }
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0xFF1DB954),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              isPlayingThisAlbum ? Icons.pause : Icons.play_arrow,
              color: Colors.black,
              size: 32,
            ),
          ),
        );
      },
    );
  }
}

class _AlbumTrackTile extends StatelessWidget {
  final int index;
  final Track track;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onMore;

  const _AlbumTrackTile({
    required this.index,
    required this.track,
    required this.onTap,
    required this.onLike,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.artist,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (track.isLiked)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.favorite,
                  color: const Color(0xFF1DB954),
                  size: 16,
                ),
              ),
            IconButton(
              icon:
                  const Icon(Icons.more_vert, color: Colors.white54, size: 20),
              onPressed: onMore,
              splashRadius: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveredTrackTile extends StatelessWidget {
  final int index;
  final DiscoveredTrack track;

  const _DiscoveredTrackTile({
    required this.index,
    required this.track,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.artistName,
                    style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.cloud_off, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }
}

class _BottomSheetHeader extends StatelessWidget {
  final String? coverPath;
  final String title;
  final String subtitle;

  const _BottomSheetHeader({
    required this.coverPath,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final exists = context.read<AppState>().coverExists(coverPath);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: const Color(0xFF2A2A2A),
              image: exists && path != null
                  ? DecorationImage(
                      image: path.startsWith('http')
                          ? NetworkImage(path) as ImageProvider
                          : FileImage(File(path)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: !exists || coverPath == null
                ? const Icon(Icons.album, color: Colors.white54, size: 24)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  const _SheetTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? Colors.white, size: 26),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
      minLeadingWidth: 24,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }
}
