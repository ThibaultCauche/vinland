import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../widgets/track_tile.dart';
import '../models/track.dart';

class ArtistScreen extends StatelessWidget {
  final String artistName;

  const ArtistScreen({super.key, required this.artistName});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        final artistTracks = state.allTracks
            .where((t) => t.artist == artistName)
            .toList()
          ..sort((a, b) => b.playCount.compareTo(a.playCount));

        final topTracks = artistTracks.take(5).toList();

        final albumNames = <String>{};
        final artistAlbums = <Map<String, dynamic>>[];
        for (final track in artistTracks) {
          if (!albumNames.contains(track.album)) {
            albumNames.add(track.album);
            final albumTracks = state.allTracks
                .where((t) => t.artist == artistName && t.album == track.album)
                .toList();
            artistAlbums.add({
              'title': track.album,
              'tracks': albumTracks,
              'count': albumTracks.length,
            });
          }
        }

        final headerColor = _generateColor(artistName);

        return PopScope(
          canPop: false,
          onPopInvoked: (didPop) {
            if (!didPop) {
              context.read<AppState>().popOverlay();
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFF121212),
            body: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 320,
                  pinned: true,
                  backgroundColor: const Color(0xFF121212),
                  iconTheme: const IconThemeData(color: Colors.white),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.read<AppState>().popOverlay(),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    centerTitle: true,
                    title: Text(
                      artistName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                      ),
                    ),
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            headerColor.withOpacity(0.9),
                            const Color(0xFF121212),
                          ],
                        ),
                      ),
                      child: SafeArea(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 40),
                            Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                color: headerColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: headerColor.withOpacity(0.4),
                                    blurRadius: 40,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  artistName.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 56,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Text(
                      '${artistTracks.length} titres · ${artistAlbums.length} album${artistAlbums.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            if (artistTracks.isNotEmpty) {
                              state.playTrack(
                                artistTracks.first,
                                trackList: artistTracks,
                              );
                            }
                          },
                          icon: const Icon(Icons.play_arrow, size: 28),
                          label: const Text(
                            'Lecture aléatoire',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'Titres populaires',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = topTracks[index];
                        return TrackTile(
                          track: track,
                          onTap: () => state.playTrack(
                            track,
                            trackList: artistTracks,
                          ),
                          onLike: () => state.toggleLike(track.id),
                        );
                      },
                      childCount: topTracks.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Text(
                      'Discographie',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
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
                        final album = artistAlbums[index];
                        return _buildAlbumCard(
                          context,
                          album['title'] as String,
                          album['count'] as int,
                          album['tracks'] as List,
                          headerColor,
                        );
                      },
                      childCount: artistAlbums.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumCard(
    BuildContext context,
    String albumTitle,
    int trackCount,
    List<dynamic> tracksDynamic,
    Color color,
  ) {
    final tracks = tracksDynamic.cast<Track>();
    String? albumCover;
    for (final track in tracks) {
      if (track.coverPath != null && File(track.coverPath!).existsSync()) {
        albumCover = track.coverPath;
        break;
      }
    }

    return GestureDetector(
      onTap: () => _openAlbumPage(context, albumTitle, tracksDynamic),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(8),
                image: albumCover != null
                    ? DecorationImage(
                        image: FileImage(File(albumCover)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: albumCover == null
                  ? Center(
                      child: Icon(
                        Icons.album,
                        color: color.withOpacity(0.6),
                        size: 48,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            albumTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '$trackCount titre${trackCount > 1 ? 's' : ''}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _openAlbumPage(
      BuildContext context, String albumTitle, List<dynamic> tracksDynamic) {
    final state = context.read<AppState>();
    final tracks = tracksDynamic.cast<Track>();

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
          title: Text(
            albumTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: ListView.builder(
          padding: const EdgeInsets.only(bottom: 120),
          itemCount: tracks.length,
          itemBuilder: (context, index) => TrackTile(
            track: tracks[index],
            onTap: () => state.playTrack(
              tracks[index],
              trackList: tracks,
            ),
            onLike: () => state.toggleLike(tracks[index].id),
          ),
        ),
      ),
    );
  }

  Color _generateColor(String text) {
    int hash = 0;
    for (var i = 0; i < text.length; i++) {
      hash = text.codeUnitAt(i) + ((hash << 5) - hash);
    }
    final hue = (hash.abs() % 360).toDouble();
    return HSVColor.fromAHSV(1.0, hue, 0.75, 0.85).toColor();
  }
}
