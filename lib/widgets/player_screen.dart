import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../screens/artist_screen.dart';
import '../screens/album_screen.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (Track?, Color?)>(
      selector: (_, state) => (state.currentTrack, state.dominantColor),
      builder: (context, data, child) {
        final (track, dominantColor) = data;
        if (track == null) return const SizedBox.shrink();

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: dominantColor != null
                ? Color.lerp(dominantColor, Colors.black, 0.4)
                : const Color(0xFF121212),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.expand_more, color: Colors.white),
              onPressed: () => context.read<AppState>().popOverlay(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () => _showPlayerOptions(context),
              ),
            ],
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  dominantColor != null
                      ? Color.lerp(dominantColor, Colors.black, 0.4)!
                      : const Color(0xFF121212),
                  const Color(0xFF121212),
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    _PlayerCover(coverPath: track.coverPath),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                track.artist,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        _LikeButton(trackId: track.id),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const _PlayerSlider(),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.shuffle,
                              color: Colors.white54, size: 28),
                          onPressed: () {},
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_previous,
                              color: Colors.white, size: 36),
                          onPressed: () =>
                              context.read<AppState>().previousTrack(),
                        ),
                        const _PlayPauseButton(),
                        IconButton(
                          icon: const Icon(Icons.skip_next,
                              color: Colors.white, size: 36),
                          onPressed: () => context.read<AppState>().nextTrack(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.repeat,
                              color: Colors.white54, size: 28),
                          onPressed: () {},
                        ),
                      ],
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPlayerOptions(BuildContext context) {
    final state = context.read<AppState>();
    final track = state.currentTrack;
    if (track == null) return;

    final coverExists = state.coverExists(track.coverPath);

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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: const Color(0xFF2A2A2A),
                      image: coverExists && track.coverPath != null
                          ? DecorationImage(
                              image: track.coverPath!.startsWith('http')
                                  ? NetworkImage(track.coverPath!)
                                      as ImageProvider
                                  : FileImage(File(track.coverPath!)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: !coverExists || track.coverPath == null
                        ? const Icon(Icons.album,
                            color: Colors.white54, size: 24)
                        : null,
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
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist,
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
            ),
            const Divider(color: Color(0xFF2A2A2A), height: 1),
            ListTile(
              leading: const Icon(Icons.add_circle_outline,
                  color: Colors.white, size: 26),
              title: const Text('Ajouter a la playlist',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                _showAddToPlaylistDialog(context, track);
              },
              minLeadingWidth: 24,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            ListTile(
              leading: Icon(
                track.isLiked ? Icons.favorite : Icons.favorite_border,
                color: track.isLiked ? const Color(0xFF1DB954) : Colors.white,
                size: 26,
              ),
              title: Text(
                track.isLiked
                    ? 'Retirer des titres likes'
                    : 'Ajouter aux titres likes',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(ctx);
                state.toggleLike(track.id);
              },
              minLeadingWidth: 24,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            ListTile(
              leading: const Icon(Icons.album_outlined,
                  color: Colors.white, size: 26),
              title: const Text("Acceder a l'album",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                final album = state.likedAlbums.firstWhere(
                  (a) => a.title == track.album,
                  orElse: () => Album(
                    id: track.album.hashCode.toString(),
                    title: track.album,
                    artist: track.artist,
                    trackIds: [],
                  ),
                );
                state.pushOverlay(AlbumScreen(album: album));
              },
              minLeadingWidth: 24,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline,
                  color: Colors.white, size: 26),
              title: const Text("Acceder a l'artiste",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                _showArtistPicker(context, track.artist);
              },
              minLeadingWidth: 24,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
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
}

class _LikeButton extends StatelessWidget {
  final String trackId;
  const _LikeButton({required this.trackId});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, bool>(
      selector: (_, state) => state.isCurrentTrackLiked,
      builder: (context, isLiked, _) => IconButton(
        icon: Icon(
          isLiked ? Icons.favorite : Icons.favorite_border,
          color: isLiked ? const Color(0xFF1DB954) : Colors.white,
        ),
        onPressed: () => context.read<AppState>().toggleLike(trackId),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton();

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, bool>(
      selector: (_, state) => state.isPlaying,
      builder: (context, isPlaying, _) => Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.black,
            size: 32,
          ),
          onPressed: () => context.read<AppState>().togglePlayPause(),
        ),
      ),
    );
  }
}

class _PlayerSlider extends StatelessWidget {
  const _PlayerSlider();

  @override
  Widget build(BuildContext context) {
    final player = context.read<AppState>().player;
    return StreamBuilder<Duration>(
      stream: Stream.periodic(
        const Duration(milliseconds: 200),
        (_) => player.position,
      ),
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        final duration = player.duration ?? Duration.zero;
        final max = duration.inSeconds.toDouble().clamp(1, 99999).toDouble();

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: position.inSeconds.toDouble().clamp(0, max).toDouble(),
                max: max,
                onChanged: (value) {
                  context
                      .read<AppState>()
                      .seek(Duration(seconds: value.toInt()));
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(position),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                Text(
                  _formatDuration(duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _PlayerCover extends StatelessWidget {
  final String? coverPath;
  const _PlayerCover({this.coverPath});

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final exists = context.read<AppState>().coverExists(coverPath);

    if (exists && path != null) {
      return Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.width - 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          image: DecorationImage(
            image: path.startsWith('http')
                ? NetworkImage(path) as ImageProvider
                : FileImage(File(path)),
            fit: BoxFit.cover,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      height: MediaQuery.of(context).size.width - 48,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.album, color: Colors.white54, size: 100),
    );
  }
}
