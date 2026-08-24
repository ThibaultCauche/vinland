import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../widgets/track_tile.dart';
import 'package:path/path.dart' as p;
import 'import_review_screen.dart';
import 'streaming_import_screen.dart';
import '../services/music_service.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import 'playlist_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchControllers = List.generate(3, (_) => TextEditingController());
  final _searchQueries = ['', '', ''];
  final _scrollControllers = List.generate(3, (_) => ScrollController());
  final _showSearchBars = [true, true, true];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _searchControllers) {
      c.dispose();
    }
    for (final c in _scrollControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _onScroll(int index, ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final show = notification.metrics.pixels <= 10;
      if (_showSearchBars[index] != show) {
        setState(() => _showSearchBars[index] = show);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (List<Track>, List<Album>, List<Playlist>)>(
      selector: (_, state) =>
          (state.likedTracks, state.likedAlbums, state.playlists),
      builder: (context, data, child) {
        final (likedTracks, likedAlbums, playlists) = data;
        final state = context.read<AppState>();
        return SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Text(
                      'Bibliotheque',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.white),
                      onPressed: () => _showImportOptions(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.playlist_add, color: Colors.white),
                      onPressed: () => _showCreatePlaylistDialog(context),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                indicatorColor: Colors.white,
                indicatorWeight: 2,
                tabs: const [
                  Tab(text: 'Titres likes'),
                  Tab(text: 'Albums'),
                  Tab(text: 'Playlists'),
                ],
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: _showSearchBars[_tabController.index] ? null : 0,
                child: _buildSearchBar(_tabController.index),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLikedTracks(state, likedTracks),
                    _buildAlbums(state, likedAlbums),
                    _buildPlaylists(state, playlists),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar(int tabIndex) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _searchControllers[tabIndex],
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Rechercher...',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Colors.white38),
          suffixIcon: _searchQueries[tabIndex].isNotEmpty
              ? IconButton(
                  icon:
                      const Icon(Icons.clear, color: Colors.white38, size: 18),
                  onPressed: () {
                    _searchControllers[tabIndex].clear();
                    setState(() => _searchQueries[tabIndex] = '');
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF2A2A2A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
        onChanged: (value) =>
            setState(() => _searchQueries[tabIndex] = value.toLowerCase()),
      ),
    );
  }

  Widget _buildLikedTracks(AppState state, List<Track> likedTracks) {
    final query = _searchQueries[0];
    final filtered = query.isEmpty
        ? likedTracks
        : likedTracks
            .where((t) =>
                t.title.toLowerCase().contains(query) ||
                t.artist.toLowerCase().contains(query) ||
                t.album.toLowerCase().contains(query))
            .toList();

    if (filtered.isEmpty) {
      return _buildEmpty(query.isEmpty ? 'Aucun titre like' : 'Aucun resultat');
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        _onScroll(0, n);
        return false;
      },
      child: ListView.builder(
        controller: _scrollControllers[0],
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: filtered.length,
        itemBuilder: (context, i) => TrackTile(
          track: filtered[i],
          onTap: () => state.playTrack(filtered[i]),
          onLike: () => state.toggleLike(filtered[i].id),
          onMore: () => _showTrackOptions(context, filtered[i]),
        ),
      ),
    );
  }

  Widget _buildAlbums(AppState state, List<Album> likedAlbums) {
    final query = _searchQueries[1];
    final filtered = query.isEmpty
        ? likedAlbums
        : likedAlbums
            .where((a) =>
                a.title.toLowerCase().contains(query) ||
                a.artist.toLowerCase().contains(query))
            .toList();

    if (filtered.isEmpty) {
      return _buildEmpty(query.isEmpty ? 'Aucun album like' : 'Aucun resultat');
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        _onScroll(1, n);
        return false;
      },
      child: GridView.builder(
        controller: _scrollControllers[1],
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, i) {
          final album = filtered[i];
          return GestureDetector(
            onTap: () {
              final appState = context.read<AppState>();
              appState.pushOverlay(AlbumScreen(album: album));
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _AlbumCoverGrid(coverPath: album.coverPath),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () => state.toggleLikeAlbum(album.id),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.favorite,
                              color: Color(0xFF1DB954),
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaylists(AppState state, List<Playlist> playlists) {
    final query = _searchQueries[2];
    final filtered = query.isEmpty
        ? playlists
        : playlists.where((p) => p.name.toLowerCase().contains(query)).toList();

    if (filtered.isEmpty) {
      return _buildEmpty(query.isEmpty ? 'Aucune playlist' : 'Aucun resultat');
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        _onScroll(2, n);
        return false;
      },
      child: ListView.builder(
        controller: _scrollControllers[2],
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: filtered.length,
        itemBuilder: (context, i) {
          final pl = filtered[i];

          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            leading: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.queue_music, color: Colors.white54),
            ),
            title: Text(
              pl.name,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${pl.trackIds.length} titre${pl.trackIds.length > 1 ? 's' : ''}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              onPressed: () => _showPlaylistOptions(context, pl),
            ),
            onTap: () {
              state.pushOverlay(PlaylistScreen(playlist: pl));
            },
          );
        },
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
            _SheetTile(
              icon: Icons.album_outlined,
              label: "Acceder a l'album",
              onTap: () {
                Navigator.pop(ctx);
                // Cherche dans TOUS les albums, pas seulement les likés
                final album = state.albums.firstWhere(
                  (a) => a.title == track.album,
                  orElse: () => Album(
                    id: track.album.hashCode.toString(),
                    title: track.album,
                    artist: track.albumArtist ?? track.artist,
                    trackIds: state.allTracks
                        .where((t) => t.album == track.album)
                        .map((t) => t.id)
                        .toList(),
                    coverPath: track.coverPath,
                  ),
                );
                state.pushOverlay(AlbumScreen(album: album));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showPlaylistOptions(BuildContext context, Playlist playlist) {
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
              coverPath: null,
              title: playlist.name,
              subtitle: '${playlist.trackIds.length} titre(s)',
            ),
            const Divider(color: Color(0xFF2A2A2A), height: 1),
            _SheetTile(
              icon: Icons.delete_outline,
              label: 'Supprimer la playlist',
              onTap: () {
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, Track track) {
    final state = context.read<AppState>();
    final playlists = state.playlists;

    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Aucune playlist. Creez-en une d'abord."),
          backgroundColor: Color(0xFF2A2A2A),
        ),
      );
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Ajoute a ${playlists[i].name}'),
                    backgroundColor: const Color(0xFF2A2A2A),
                  ),
                );
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

  Widget _buildEmpty(String text) {
    return Center(
      child: Text(text, style: const TextStyle(color: Colors.white38)),
    );
  }

  void _showImportOptions(BuildContext context) {
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Importer de la musique',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.folder, color: Color(0xFF1DB954)),
                title: const Text('Depuis un dossier',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('Scanner un dossier et ses sous-dossiers',
                    style: TextStyle(color: Colors.white54)),
                onTap: () {
                  Navigator.pop(context);
                  _pickFolder(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.audio_file, color: Color(0xFF1DB954)),
                title: const Text('Fichiers individuels',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('Selectionner des fichiers un par un',
                    style: TextStyle(color: Colors.white54)),
                onTap: () {
                  Navigator.pop(context);
                  _pickFiles(context);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.cloud_download, color: Color(0xFF1DB954)),
                title: const Text('Depuis un service de streaming',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Spotify, YouTube Music, Deezer, Tidal, Apple Music...',
                  style: TextStyle(color: Colors.white54),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const StreamingImportScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFiles(BuildContext context) async {
    final nav = Navigator.of(context);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'flac', 'm4a', 'ogg', 'wav'],
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final paths = result.files.map((f) => f.path!).toList();
      nav.push(
        MaterialPageRoute(
          builder: (_) => ImportReviewScreen(filePaths: paths),
        ),
      );
    }
  }

  Future<void> _pickFolder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    PermissionStatus status;
    if (Platform.isAndroid) {
      status = await Permission.audio.request();
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
    } else {
      status = await Permission.storage.request();
    }

    if (!status.isGranted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Permission de stockage refusee'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      final files = <String>[];

      try {
        final dir = Directory(selectedDirectory);
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (['.mp3', '.flac', '.m4a', '.ogg', '.wav'].contains(ext)) {
              files.add(entity.path);
            }
          }
        }
      } catch (e) {
        print('ERREUR LECTURE DOSSIER: $e');
      }

      if (files.isNotEmpty) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => ImportReviewScreen(filePaths: files),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Aucun fichier musical trouve dans ce dossier'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Nouvelle playlist',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Nom de la playlist',
            hintStyle: TextStyle(color: Colors.white38),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF2A2A2A)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                context.read<AppState>().createPlaylist(controller.text);
                Navigator.pop(context);
              }
            },
            child:
                const Text('Creer', style: TextStyle(color: Color(0xFF1DB954))),
          ),
        ],
      ),
    );
  }
}

class _AlbumCoverGrid extends StatelessWidget {
  final String? coverPath;
  const _AlbumCoverGrid({this.coverPath});

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
                image: path.startsWith('http')
                    ? NetworkImage(path) as ImageProvider
                    : FileImage(File(path)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: exists != true
          ? const Center(
              child: Icon(Icons.album, color: Colors.white54, size: 48),
            )
          : null,
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
