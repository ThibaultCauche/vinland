import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/recent_play.dart';
import '../widgets/track_tile.dart';
import '../widgets/download_button.dart';
import '../widgets/bottom_sheet_common.dart';
import '../widgets/playlist_options_sheet.dart';
import '../widgets/playlist_cover.dart';
import 'artist_screen.dart';
import 'album_screen.dart';
import '../models/album.dart';
import '../services/deep_link_service.dart';
import '../widgets/bottom_bar_reserve.dart';

class PlaylistScreen extends StatelessWidget {
  final Playlist playlist;

  /// Vrai pour la playlist d'un ami consultee depuis son profil : aucune
  /// action de modification (supprimer, retirer un titre, rendre publique)
  /// n'est proposee, seule la lecture et le like des titres restent possibles.
  final bool readOnly;

  const PlaylistScreen(
      {super.key, required this.playlist, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, List<Track>>(
      selector: (_, state) {
        return state.allTracks
            .where((t) => playlist.trackIds.contains(t.id))
            .toList();
      },
      builder: (context, tracks, child) {
        final state = context.read<AppState>();

        void recordRecent() {
          state.recordRecentPlay(RecentPlay(
            type: RecentPlayType.playlist,
            id: playlist.id,
            title: playlist.name,
            subtitle:
                '${playlist.trackIds.length} titre${playlist.trackIds.length > 1 ? 's' : ''}',
            playedAt: DateTime.now(),
          ));
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => state.popOverlay(),
            ),
            title: Text(playlist.name,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            actions: readOnly
                ? [
                    IconButton(
                      icon: const Icon(Icons.playlist_add, color: Colors.white),
                      tooltip: 'Ajouter à ma bibliothèque',
                      onPressed: () => _copyToLibrary(context, state, playlist),
                    ),
                  ]
                : [
                    IconButton(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onPressed: () => showPlaylistOptions(context, playlist,
                          onDeleted: state.popOverlay),
                    ),
                  ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    PlaylistCover(
                      playlist: playlist,
                      size: 120,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playlist.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${playlist.trackIds.length} titre${playlist.trackIds.length > 1 ? 's' : ''}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: tracks.isNotEmpty
                          ? () {
                              recordRecent();
                              state.playTrack(tracks.first, trackList: tracks);
                            }
                          : null,
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
                      onPressed: tracks.isNotEmpty
                          ? () {
                              recordRecent();
                              final shuffled = List.of(tracks)..shuffle();
                              state.playTrack(shuffled.first,
                                  trackList: shuffled);
                            }
                          : null,
                    ),
                    const SizedBox(width: 4),
                    DownloadButton(
                      tracks: tracks,
                      confirmDeleteMessage:
                          'Cette playlist ne sera plus disponible hors connexion.',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: tracks.isEmpty
                    ? const Center(
                        child: Text('Aucun titre dans cette playlist',
                            style: TextStyle(color: Colors.white38)),
                      )
                    : ListView.builder(
                        key: PageStorageKey('playlist_${playlist.id}'),
                        padding:
                            EdgeInsets.only(bottom: bottomBarReserve(context)),
                        itemCount: tracks.length,
                        itemBuilder: (context, i) => Selector<AppState, Track?>(
                          selector: (_, s) => s.currentTrack,
                          builder: (context, currentTrack, __) => TrackTile(
                            track: tracks[i],
                            isPlaying: currentTrack?.id == tracks[i].id,
                            onTap: () {
                              recordRecent();
                              state.playTrack(tracks[i], trackList: tracks);
                            },
                            onLike: () => state.toggleLike(tracks[i].id),
                            onMore: () => _showTrackOptions(context, tracks[i],
                                readOnly: readOnly),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _copyToLibrary(
      BuildContext context, AppState state, Playlist playlist) async {
    final messenger = ScaffoldMessenger.of(context);
    await state.copyFriendPlaylist(playlist);
    messenger.showSnackBar(SnackBar(
      content: Text('"${playlist.name}" ajoutée à ta bibliothèque'),
    ));
  }

  void _showTrackOptions(BuildContext context, Track track,
      {bool readOnly = false}) {
    final state = context.read<AppState>();
    showOptionsSheet(context,
        builder: (ctx) => [
              BottomSheetHeader(
                coverPath: track.coverPath,
                title: track.title,
                subtitle: track.artist,
              ),
              const Divider(color: Color(0xFF2A2A2A), height: 1),
              if (!readOnly)
                SheetTile(
                  icon: Icons.remove_circle_outline,
                  label: 'Retirer de la playlist',
                  onTap: () {
                    Navigator.pop(ctx);
                    state.removeFromPlaylist(playlist.id, track.id);
                  },
                ),
              SheetTile(
                icon: Icons.playlist_play,
                label: 'Lire ensuite',
                onTap: () {
                  Navigator.pop(ctx);
                  state.playNext(track);
                },
              ),
              SheetTile(
                icon: Icons.queue_music,
                label: "Ajouter a la file d'attente",
                onTap: () {
                  Navigator.pop(ctx);
                  state.addToQueue(track);
                },
              ),
              SheetTile(
                icon: track.isLiked ? Icons.favorite : Icons.favorite_border,
                label: track.isLiked
                    ? 'Retirer des titres likes'
                    : 'Ajouter aux titres likes',
                iconColor:
                    track.isLiked ? const Color(0xFF1DB954) : Colors.white,
                onTap: () {
                  Navigator.pop(ctx);
                  state.toggleLike(track.id);
                },
              ),
              SheetTile(
                icon: Icons.album_outlined,
                label: "Acceder a l'album",
                onTap: () {
                  Navigator.pop(ctx);
                  // Match par albumId Navidrome quand il existe : deux albums
                  // differents peuvent partager le meme titre, matcher par
                  // titre seul pouvait ouvrir le mauvais album.
                  final expectedId = track.albumId != null
                      ? 'navidrome_${track.albumId}'
                      : null;
                  final album = state.likedAlbums.firstWhere(
                    (a) => expectedId != null
                        ? a.id == expectedId
                        : a.title == track.album,
                    orElse: () => Album(
                      id: expectedId ?? track.album.hashCode.toString(),
                      title: track.album,
                      artist: track.artist,
                      trackIds: [],
                    ),
                  );
                  state.pushOverlay(AlbumScreen(album: album));
                },
              ),
              SheetTile(
                icon: Icons.person_outline,
                label: "Acceder a l'artiste",
                onTap: () {
                  Navigator.pop(ctx);
                  state.pushOverlay(ArtistScreen(artistName: track.artist));
                },
              ),
              SheetTile(
                icon: Icons.ios_share,
                label: 'Partager',
                onTap: () {
                  Navigator.pop(ctx);
                  shareTrack(track);
                },
              ),
              if (state.shareInboxConfigured)
                SheetTile(
                  icon: Icons.send_outlined,
                  label: 'Envoyer a un ami',
                  onTap: () {
                    Navigator.pop(ctx);
                    showSendToFriendDialog(context,
                        type: 'track',
                        itemId: track.id,
                        title: track.title,
                        subtitle: track.artist);
                  },
                ),
              const SizedBox(height: 8),
            ]);
  }
}
