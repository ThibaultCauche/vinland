import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../widgets/track_tile.dart';
import '../models/album.dart';

class ArtistScreen extends StatelessWidget {
  final String artistName;

  const ArtistScreen({super.key, required this.artistName});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        final artistTracks =
            state.allTracks.where((t) => t.artist == artistName).toList();
        final albums =
            state.albums.where((a) => a.artist == artistName).toList();

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => state.popOverlay(),
            ),
            title: Text(artistName,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _ArtistAvatar(
                        coverPath:
                            albums.isNotEmpty ? albums.first.coverPath : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              artistName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${artistTracks.length} titres',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          if (artistTracks.isNotEmpty) {
                            state.playTrack(artistTracks.first,
                                trackList: artistTracks);
                          }
                        },
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
                        onPressed: () {
                          if (artistTracks.isNotEmpty) {
                            final shuffled = List.of(artistTracks)..shuffle();
                            state.playTrack(shuffled.first,
                                trackList: shuffled);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  child: Text(
                    'Albums',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final album = albums[index];
                      return _buildAlbumCard(context, album, state);
                    },
                    childCount: albums.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  child: Text(
                    'Titres',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => TrackTile(
                      track: artistTracks[index],
                      onTap: () => state.playTrack(artistTracks[index]),
                      onLike: () => state.toggleLike(artistTracks[index].id),
                    ),
                    childCount: artistTracks.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlbumCard(BuildContext context, Album album, AppState state) {
    final albumTracks =
        state.allTracks.where((t) => t.album == album.title).toList();

    return GestureDetector(
      onTap: () {
        state.pushOverlay(
          Scaffold(
            backgroundColor: const Color(0xFF121212),
            appBar: AppBar(
              backgroundColor: const Color(0xFF121212),
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => state.popOverlay(),
              ),
              title: Text(album.title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            body: ListView.builder(
              padding: const EdgeInsets.only(bottom: 120),
              itemCount: albumTracks.length,
              itemBuilder: (context, index) => TrackTile(
                track: albumTracks[index],
                onTap: () =>
                    state.playTrack(albumTracks[index], trackList: albumTracks),
                onLike: () => state.toggleLike(albumTracks[index].id),
              ),
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _AlbumCover(coverPath: album.coverPath),
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
            '${albumTracks.length} titres',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ArtistAvatar extends StatefulWidget {
  final String? coverPath;
  const _ArtistAvatar({this.coverPath});

  @override
  State<_ArtistAvatar> createState() => _ArtistAvatarState();
}

class _ArtistAvatarState extends State<_ArtistAvatar> {
  bool? _exists;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant _ArtistAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverPath != widget.coverPath) _check();
  }

  void _check() async {
    final path = widget.coverPath;
    if (path == null) {
      if (mounted) setState(() => _exists = false);
      return;
    }
    final result = await File(path).exists();
    if (mounted) setState(() => _exists = result);
  }

  @override
  Widget build(BuildContext context) {
    if (_exists == true) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          image: DecorationImage(
            image: FileImage(File(widget.coverPath!)),
            fit: BoxFit.cover,
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

class _AlbumCover extends StatefulWidget {
  final String? coverPath;
  const _AlbumCover({this.coverPath});

  @override
  State<_AlbumCover> createState() => _AlbumCoverState();
}

class _AlbumCoverState extends State<_AlbumCover> {
  bool? _exists;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant _AlbumCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverPath != widget.coverPath) _check();
  }

  void _check() async {
    final path = widget.coverPath;
    if (path == null) {
      if (mounted) setState(() => _exists = false);
      return;
    }
    final result = await File(path).exists();
    if (mounted) setState(() => _exists = result);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        image: _exists == true
            ? DecorationImage(
                image: FileImage(File(widget.coverPath!)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: _exists != true
          ? const Center(
              child: Icon(Icons.album, color: Colors.white54, size: 48),
            )
          : null,
    );
  }
}
