import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/track.dart';
import 'glass.dart';

/// Accueil desktop : shelves horizontales dans des cartes en verre, comme
/// la home mobile mais redimensionnee pour un grand ecran.
class DesktopHomeView extends StatelessWidget {
  final ValueChanged<Album> onOpenAlbum;
  final ValueChanged<Track> onPlayTrackShelf;
  final ValueChanged<String> onOpenArtist;

  const DesktopHomeView({
    super.key,
    required this.onOpenAlbum,
    required this.onPlayTrackShelf,
    required this.onOpenArtist,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (List<Album>, List<Track>, String?)>(
      selector: (_, state) => (state.albums, state.allTracks, state.userName),
      builder: (context, data, __) {
        final (albums, allTracks, userName) = data;

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Text(
              'Bonjour${userName != null ? ', $userName' : ''}',
              style: const TextStyle(
                  color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _sectionTitle('Écoutés cette semaine'),
            _trackShelf(context, _weeklyTracks(allTracks)),
            _sectionTitle('Artistes du moment'),
            _artistShelf(context, allTracks),
            _sectionTitle('Découverte'),
            _albumShelf(context, _discoveryAlbums(albums, allTracks)),
            _sectionTitle('Nouveautés du NAS'),
            _albumShelf(context, _newOnServer(albums)),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 12),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
      );

  List<Track> _weeklyTracks(List<Track> allTracks) {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final recent = allTracks
        .where((t) => t.playCount > 0 && t.lastPlayed != null && t.lastPlayed!.isAfter(weekAgo))
        .toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    return recent.take(10).toList();
  }

  List<Album> _discoveryAlbums(List<Album> albums, List<Track> allTracks) {
    final tracksById = {for (final t in allTracks) t.id: t};
    final notLiked = albums.where((a) {
      if (a.isSaved) return false;
      return a.trackIds.every((id) => tracksById[id]?.isLiked != true);
    }).toList();
    final today = DateTime.now();
    final seed = today.year * 10000 + today.month * 100 + today.day;
    return (List<Album>.of(notLiked)..shuffle(Random(seed))).take(10).toList();
  }

  List<Album> _newOnServer(List<Album> albums) {
    final withDate = albums.where((a) => a.addedToServerAt != null).toList()
      ..sort((a, b) => b.addedToServerAt!.compareTo(a.addedToServerAt!));
    return withDate.take(10).toList();
  }

  Widget _emptyShelf(String text) => SizedBox(
        height: 60,
        child: Center(child: Text(text, style: const TextStyle(color: Colors.white38))),
      );

  Widget _trackShelf(BuildContext context, List<Track> tracks) {
    if (tracks.isEmpty) return _emptyShelf('Pas encore assez d\'écoutes cette semaine');
    final state = context.read<AppState>();
    return SizedBox(
      height: 210,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tracks.length,
        itemBuilder: (context, i) {
          final track = tracks[i];
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              width: 150,
              child: GestureDetector(
                onTap: () => state.playTrack(track, trackList: tracks),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShelfCover(coverPath: track.coverPath, size: 150),
                    const SizedBox(height: 8),
                    Text(track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _albumShelf(BuildContext context, List<Album> albums) {
    if (albums.isEmpty) return _emptyShelf('Rien a afficher pour le moment');
    return SizedBox(
      height: 210,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: albums.length,
        itemBuilder: (context, i) {
          final album = albums[i];
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              width: 150,
              child: GestureDetector(
                onTap: () => onOpenAlbum(album),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShelfCover(coverPath: album.coverPath, size: 150),
                    const SizedBox(height: 8),
                    Text(album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(album.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _artistShelf(BuildContext context, List<Track> allTracks) {
    final playsByArtist = <String, int>{};
    final coverByArtist = <String, String?>{};
    for (final t in allTracks) {
      if (t.playCount <= 0) continue;
      playsByArtist.update(t.artist, (v) => v + t.playCount, ifAbsent: () => t.playCount);
      coverByArtist.putIfAbsent(t.artist, () => t.coverPath);
    }
    final artists = playsByArtist.keys.toList()
      ..sort((a, b) => playsByArtist[b]!.compareTo(playsByArtist[a]!));

    if (artists.isEmpty) {
      return _emptyShelf('Écoutez de la musique pour voir vos artistes ici');
    }

    final picks = artists.take(10).toList();
    return SizedBox(
      height: 160,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: picks.length,
        itemBuilder: (context, i) {
          final artist = picks[i];
          return Padding(
            padding: const EdgeInsets.only(right: 20),
            child: SizedBox(
              width: 104,
              child: GestureDetector(
                onTap: () => onOpenArtist(artist),
                child: Column(
                  children: [
                    ClipOval(
                      child: _ShelfCover(coverPath: coverByArtist[artist], size: 96),
                    ),
                    const SizedBox(height: 8),
                    Text(artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ShelfCover extends StatelessWidget {
  final String? coverPath;
  final double size;
  const _ShelfCover({required this.coverPath, required this.size});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final exists = context.read<AppState>().coverExists(path);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
        image: exists && path != null
            ? DecorationImage(
                image: path.startsWith('http')
                    ? NetworkImage(path) as ImageProvider
                    : FileImage(File(path)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: !exists ? const Icon(Icons.album, color: Colors.white54, size: 36) : null,
    );
  }
}
