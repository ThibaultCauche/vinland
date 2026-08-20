import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/discovered_album.dart';
import '../models/discovered_artist.dart';
import '../services/discovery_service.dart';
import '../widgets/track_tile.dart';
import 'album_screen.dart';
import 'discovered_album_screen.dart';

class ArtistScreen extends StatefulWidget {
  final String artistName;

  const ArtistScreen({super.key, required this.artistName});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  final _discovery = DiscoveryService();

  DiscoveredArtist? _discoveredArtist;
  List<DiscoveredAlbum> _discoveredAlbums = [];
  bool _loadingDeezer = true;

  @override
  void initState() {
    super.initState();
    _loadDeezerData();
  }

  Future<void> _loadDeezerData() async {
    // 1. Cherche l'artiste sur Deezer
    final artists = await _discovery.searchArtists(widget.artistName, limit: 5);
    DiscoveredArtist? match;
    for (final a in artists) {
      if (_normalize(a.name) == _normalize(widget.artistName)) {
        match = a;
        break;
      }
    }

    if (match != null) {
      _discoveredArtist = match;
      _discoveredAlbums = await _discovery.getArtistAlbums(match.id, limit: 50);
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

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (List<Track>, List<Album>)>(
      selector: (_, state) {
        final tracks = state.allTracks
            .where((t) => t.artist == widget.artistName)
            .toList();
        final albums =
            state.albums.where((a) => a.artist == widget.artistName).toList();
        return (tracks, albums);
      },
      builder: (context, data, child) {
        final (artistTracks, localAlbums) = data;
        final state = context.read<AppState>();

        // Fusion : albums locaux d'abord, puis découvertes non présentes
        final discoveredOnly =
            _discoveredAlbums.where((d) => !d.isInLibrary).toList();
        final totalAlbumCount = localAlbums.length + discoveredOnly.length;

        // Image de l'artiste
        final artistImage = _discoveredArtist?.pictureBigUrl ??
            (localAlbums.isNotEmpty ? localAlbums.first.coverPath : null);

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => state.popOverlay(),
            ),
            title: Text(widget.artistName,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          body: CustomScrollView(
            slivers: [
              // ── HEADER ──
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
                              '${artistTracks.length} titres locaux',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 14),
                            ),
                            if (_discoveredAlbums.isNotEmpty)
                              Text(
                                '${_discoveredAlbums.length} albums sur Deezer',
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

              // ── ACTIONS ──
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

              // ── ALBUMS ──
              if (totalAlbumCount > 0) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
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
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index < localAlbums.length) {
                          return _LocalAlbumCard(
                            album: localAlbums[index],
                            state: state,
                          );
                        } else {
                          final disc =
                              discoveredOnly[index - localAlbums.length];
                          return _DiscoveredAlbumCard(
                            album: disc,
                            state: state,
                          );
                        }
                      },
                      childCount: totalAlbumCount,
                    ),
                  ),
                ),
              ] else if (_loadingDeezer) ...[
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

              // ── TITRES LOCAUX ──
              if (artistTracks.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
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
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
    );
  }
}

// ── CARTE ALBUM LOCAL ──
class _LocalAlbumCard extends StatelessWidget {
  final Album album;
  final AppState state;

  const _LocalAlbumCard({required this.album, required this.state});

  @override
  Widget build(BuildContext context) {
    final albumTracks =
        state.allTracks.where((t) => t.album == album.title).toList();

    return GestureDetector(
      onTap: () => state.pushOverlay(AlbumScreen(album: album)),
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

// ── CARTE ALBUM DÉCOUVERT (GRISÉ) ──
class _DiscoveredAlbumCard extends StatelessWidget {
  final DiscoveredAlbum album;
  final AppState state;

  const _DiscoveredAlbumCard({required this.album, required this.state});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => state.pushOverlay(DiscoveredAlbumScreen(album: album)),
      child: Opacity(
        opacity: 0.45,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(8),
                  image: album.coverUrl != null
                      ? DecorationImage(
                          image: NetworkImage(album.coverUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: album.coverUrl == null
                    ? const Center(
                        child:
                            Icon(Icons.album, color: Colors.white54, size: 48))
                    : null,
              ),
            ),
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
  }
}

// ── WIDGETS RÉUTILISABLES ──

class _ArtistAvatar extends StatelessWidget {
  final String? url;
  const _ArtistAvatar({this.url});

  @override
  Widget build(BuildContext context) {
    final imageUrl = url; // ← variable locale

    if (imageUrl != null && imageUrl.startsWith('http')) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          image: DecorationImage(
            image: NetworkImage(imageUrl),
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    if (imageUrl != null) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          image: DecorationImage(
            image: FileImage(File(imageUrl)),
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

class _AlbumCover extends StatelessWidget {
  final String? coverPath;
  const _AlbumCover({this.coverPath});

  @override
  Widget build(BuildContext context) {
    final path = coverPath; // ← variable locale
    final exists = context.read<AppState>().coverExists(path);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        image: exists && path != null
            ? DecorationImage(
                image: FileImage(File(path)),
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
