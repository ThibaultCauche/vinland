import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/collab_playlist.dart';
import '../models/recent_play.dart';
import '../widgets/track_tile.dart';
import '../widgets/download_button.dart';
import '../widgets/bottom_bar_reserve.dart';

/// Vue fusionnee d'une playlist collaborative (voir MusicService.
/// fetchCollabPlaylist) : contrairement a PlaylistScreen, le contenu affiche
/// n'est pas playlist.trackIds (qui ne contient QUE les ajouts de
/// l'utilisateur courant) mais la fusion de toutes les sous-listes des
/// participants, recuperee a l'ouverture. Retirer un titre n'est possible
/// que sur ses propres ajouts (l'API Navidrome n'autorise pas d'editer la
/// sous-liste de quelqu'un d'autre).
class CollabPlaylistScreen extends StatefulWidget {
  final Playlist playlist;
  const CollabPlaylistScreen({super.key, required this.playlist});

  @override
  State<CollabPlaylistScreen> createState() => _CollabPlaylistScreenState();
}

class _CollabPlaylistScreenState extends State<CollabPlaylistScreen> {
  CollabPlaylistView? _view;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final view =
        await state.fetchCollabPlaylist(widget.playlist.collabGroupId!);
    if (!mounted) return;
    setState(() {
      _view = view;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, List<Track>>(
      selector: (_, state) {
        final ids = _view?.trackIds ?? const <String>[];
        return state.allTracks.where((t) => ids.contains(t.id)).toList();
      },
      builder: (context, allTracks, child) {
        final state = context.read<AppState>();
        final view = _view;
        final orderedIds = view?.trackIds ?? const <String>[];
        final byId = {for (final t in allTracks) t.id: t};
        final tracks =
            orderedIds.map((id) => byId[id]).whereType<Track>().toList();
        final myUsername = state.userName;

        void recordRecent() {
          state.recordRecentPlay(RecentPlay(
            type: RecentPlayType.playlist,
            id: widget.playlist.id,
            title: widget.playlist.name,
            subtitle: '${tracks.length} titre${tracks.length > 1 ? 's' : ''}',
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
            title: Text(widget.playlist.name,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_add_alt, color: Colors.white),
                onPressed: () => _shareCode(context),
              ),
            ],
          ),
          body: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF1DB954)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.groups,
                                color: Colors.white54, size: 48),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.playlist.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Collaborative · ${tracks.length} titre${tracks.length > 1 ? 's' : ''}',
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
                                    state.playTrack(tracks.first,
                                        trackList: tracks);
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
                            icon:
                                const Icon(Icons.shuffle, color: Colors.white),
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
                              padding: EdgeInsets.only(
                                  bottom: bottomBarReserve(context)),
                              itemCount: tracks.length,
                              itemBuilder: (context, i) {
                                final track = tracks[i];
                                final addedBy = view?.addedBy[track.id];
                                final isMine =
                                    addedBy != null && addedBy == myUsername;
                                return Selector<AppState, Track?>(
                                  selector: (_, s) => s.currentTrack,
                                  builder: (context, currentTrack, __) =>
                                      TrackTile(
                                    track: track,
                                    isPlaying: currentTrack?.id == track.id,
                                    onTap: () {
                                      recordRecent();
                                      state.playTrack(track, trackList: tracks);
                                    },
                                    onLike: () => state.toggleLike(track.id),
                                    onMore: () => _showTrackOptions(
                                        context, track,
                                        addedBy: addedBy, isMine: isMine),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  void _shareCode(BuildContext context) {
    final groupId = widget.playlist.collabGroupId!;
    Clipboard.setData(ClipboardData(text: groupId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Code copie : $groupId'),
        backgroundColor: const Color(0xFF2A2A2A),
      ),
    );
  }

  void _showTrackOptions(BuildContext context, Track track,
      {String? addedBy, required bool isMine}) {
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
            ListTile(
              title: Text(track.title,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: Text(
                addedBy != null ? 'Ajoute par $addedBy' : track.artist,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
            const Divider(color: Color(0xFF2A2A2A), height: 1),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline,
                    color: Colors.white, size: 26),
                title: const Text('Retirer de la playlist',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await state.musicService
                      .removeFromPlaylist(widget.playlist.id, track.id);
                  if (!mounted) return;
                  setState(() => _loading = true);
                  await _load();
                },
                minLeadingWidth: 24,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ListTile(
              leading: Icon(
                  track.isLiked ? Icons.favorite : Icons.favorite_border,
                  color: track.isLiked ? const Color(0xFF1DB954) : Colors.white,
                  size: 26),
              title: Text(
                  track.isLiked
                      ? 'Retirer des titres likes'
                      : 'Ajouter aux titres likes',
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
              onTap: () {
                Navigator.pop(ctx);
                state.toggleLike(track.id);
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
}
