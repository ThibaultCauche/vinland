import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/discovered_album.dart';
import '../models/discovered_track.dart';
import '../models/track.dart';
import '../services/discovery_service.dart';
import 'artist_screen.dart';

class DiscoveredAlbumScreen extends StatefulWidget {
  final DiscoveredAlbum? album;
  final int? albumId;
  final String? filterArtist; // ← NOUVEAU : filtre les tracks par artiste

  const DiscoveredAlbumScreen({
    super.key,
    this.album,
    this.albumId,
    this.filterArtist,
  }) : assert(album != null || albumId != null);

  factory DiscoveredAlbumScreen.fromAlbumId(int id, {String? filterArtist}) {
    return DiscoveredAlbumScreen(albumId: id, filterArtist: filterArtist);
  }

  @override
  State<DiscoveredAlbumScreen> createState() => _DiscoveredAlbumScreenState();
}

class _DiscoveredAlbumScreenState extends State<DiscoveredAlbumScreen> {
  final _discovery = DiscoveryService();
  DiscoveredAlbum? _album;
  List<DiscoveredTrack> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.album != null) {
      _album = widget.album;
    } else if (widget.albumId != null) {
      _album = await _discovery.getAlbum(widget.albumId!);
    }

    if (_album != null) {
      _tracks = await _discovery.getAlbumTracks(_album!.id);
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// Vérifie si l'artiste recherché est présent dans le champ artiste
  bool _artistContains(String? artistField, String search) {
    if (artistField == null) return false;
    final s = search.toLowerCase();
    final f = artistField.toLowerCase();
    if (f == s) return true;
    if (f.contains(s)) return true;
    return f.split(RegExp(r'[/&,]')).any((p) => p.trim() == s);
  }

  /// Trouve la track locale correspondante à une track Deezer
  Track? _findLocalTrack(DiscoveredTrack dt) {
    final state = context.read<AppState>();
    final localTracks = state.allTracks;

    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final dtArtist = norm(dt.artistName);
    final dtTitle = norm(dt.title);
    final dtAlbum = norm(dt.albumName);

    for (final lt in localTracks) {
      final ltArtist = norm(lt.artist);
      final ltTitle = norm(lt.title);
      final ltAlbum = norm(lt.album);

      final artistMatch = ltArtist == dtArtist ||
          ltArtist.contains(dtArtist) ||
          dtArtist.contains(ltArtist);
      final titleMatch = ltTitle == dtTitle ||
          ltTitle.contains(dtTitle) ||
          dtTitle.contains(ltTitle);
      final albumMatch = ltAlbum == dtAlbum ||
          ltAlbum.contains(dtAlbum) ||
          dtAlbum.contains(ltAlbum);

      if (artistMatch && titleMatch && albumMatch) {
        return lt;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final album = _album;

    if (_isLoading || album == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF1DB954)),
        ),
      );
    }

    // Filtre les tracks si filterArtist est fourni
    final displayTracks = widget.filterArtist != null
        ? _tracks
            .where((t) => _artistContains(t.artistName, widget.filterArtist!))
            .toList()
        : _tracks;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => state.popOverlay(),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                        image: album.coverBigUrl != null
                            ? DecorationImage(
                                image: NetworkImage(album.coverBigUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                        color: const Color(0xFF2A2A2A),
                      ),
                      child: album.coverBigUrl == null
                          ? const Icon(Icons.album,
                              color: Colors.white54, size: 64)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    album.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      state.pushOverlay(
                        ArtistScreen(artistName: album.artistName),
                      );
                    },
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: const Color(0xFF3E3E3E),
                          backgroundImage: album.coverUrl != null
                              ? NetworkImage(album.coverUrl!)
                              : null,
                          child: album.coverUrl == null
                              ? const Icon(Icons.person,
                                  color: Colors.white54, size: 12)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          album.artistName,
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
                    'Album • ${displayTracks.length} titres',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _DiscoveredTrackTile(
                  index: index,
                  track: displayTracks[index],
                  onTap: () {
                    if (displayTracks[index].isInLibrary) {
                      final localTrack = _findLocalTrack(displayTracks[index]);
                      if (localTrack != null) {
                        state.playTrack(localTrack);
                      }
                    }
                  },
                ),
                childCount: displayTracks.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 220)),
        ],
      ),
    );
  }
}

class _DiscoveredTrackTile extends StatelessWidget {
  final int index;
  final DiscoveredTrack track;
  final VoidCallback onTap;

  const _DiscoveredTrackTile({
    required this.index,
    required this.track,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: track.isInLibrary ? onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: track.isInLibrary ? Colors.white54 : Colors.white38,
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
                    style: TextStyle(
                      color: track.isInLibrary ? Colors.white : Colors.white38,
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
                    style: TextStyle(
                      color:
                          track.isInLibrary ? Colors.white54 : Colors.white24,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (track.isInLibrary)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.check_circle,
                    color: Color(0xFF1DB954), size: 16),
              )
            else
              const Icon(Icons.cloud_off, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }
}
