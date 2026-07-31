import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/app_state.dart';
import '../widgets/track_tile.dart';
import 'package:path/path.dart' as p;
import 'import_review_screen.dart';
import 'streaming_import_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return SafeArea(
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
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLikedTracks(state),
                    _buildAlbums(state),
                    _buildPlaylists(state),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
                    style: TextStyle(color: Colors.white54)),
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

  Widget _buildLikedTracks(AppState state) {
    if (state.likedTracks.isEmpty) {
      return _buildEmpty('Aucun titre like');
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: state.likedTracks.length,
      itemBuilder: (context, i) => TrackTile(
        track: state.likedTracks[i],
        onTap: () => state.playTrack(state.likedTracks[i]),
        onLike: () => state.toggleLike(state.likedTracks[i].id),
      ),
    );
  }

  Widget _buildAlbums(AppState state) {
    final savedAlbums = state.albums;

    if (savedAlbums.isEmpty) {
      return _buildEmpty('Aucun album');
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: savedAlbums.length,
      itemBuilder: (context, i) {
        final album = savedAlbums[i];
        final albumTracks =
            state.allTracks.where((t) => t.album == album.title).toList();

        return GestureDetector(
          onTap: () {
            final appState = context.read<AppState>();
            appState.pushOverlay(
              Scaffold(
                backgroundColor: const Color(0xFF121212),
                appBar: AppBar(
                  backgroundColor: const Color(0xFF121212),
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => appState.popOverlay(),
                  ),
                  title: Text(
                    album.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                body: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 120),
                  itemCount: albumTracks.length,
                  itemBuilder: (context, index) => TrackTile(
                    track: albumTracks[index],
                    onTap: () => appState.playTrack(
                      albumTracks[index],
                      trackList: albumTracks,
                    ),
                    onLike: () => appState.toggleLike(albumTracks[index].id),
                  ),
                ),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                    image: album.coverPath != null &&
                            File(album.coverPath!).existsSync()
                        ? DecorationImage(
                            image: FileImage(File(album.coverPath!)),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: album.coverPath == null ||
                          !File(album.coverPath!).existsSync()
                      ? const Center(
                          child: Icon(Icons.album,
                              color: Colors.white54, size: 48),
                        )
                      : null,
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
    );
  }

  Widget _buildPlaylists(AppState state) {
    return _buildEmpty('Aucune playlist');
  }

  Widget _buildEmpty(String text) {
    return Center(
      child: Text(text, style: const TextStyle(color: Colors.white38)),
    );
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
