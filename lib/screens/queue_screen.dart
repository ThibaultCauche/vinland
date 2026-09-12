import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../widgets/app_background.dart';
import '../widgets/cover_image.dart';
import '../services/music_service.dart';

/// "File d'attente" façon Spotify : titre en cours + titres à venir,
/// réordonnables par glisser-déposer (poignée dédiée, pour ne pas entrer en
/// conflit avec le tap "lire ce titre maintenant"). Alimentée par
/// AppState.queue -- voir le commentaire sur ce champ pour le contexte
/// (un seul titre à la fois est confié au moteur audio désormais, la file
/// visible ici est intégralement gérée côté app).
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (Track?, List<Track>)>(
      selector: (_, state) => (state.currentTrack, state.queue),
      builder: (context, data, child) {
        final (currentTrack, queue) = data;
        final state = context.read<AppState>();

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.expand_more, color: Colors.white),
              onPressed: () => state.popOverlay(),
            ),
            title: const Text('File d\'attente',
                style: TextStyle(color: Colors.white)),
          ),
          body: AppBackground(
            child: currentTrack == null
                ? const Center(
                    child: Text('Rien en cours de lecture',
                        style: TextStyle(color: Colors.white38)),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text('En cours de lecture',
                            style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                      _CurrentTrackTile(track: currentTrack),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          'Ensuite'
                          '${queue.isNotEmpty ? ' (${queue.length})' : ''}',
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: queue.isEmpty
                            ? const Center(
                                child: Text('Aucun titre à venir',
                                    style: TextStyle(color: Colors.white38)),
                              )
                            : ReorderableListView.builder(
                                padding: const EdgeInsets.only(bottom: 24),
                                itemCount: queue.length,
                                onReorder: state.reorderQueue,
                                itemBuilder: (context, i) => _QueueTile(
                                  key: ValueKey('queue-$i-${queue[i].id}'),
                                  index: i,
                                  track: queue[i],
                                ),
                              ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _CurrentTrackTile extends StatelessWidget {
  final Track track;
  const _CurrentTrackTile({required this.track});

  @override
  Widget build(BuildContext context) {
    final coverExists =
        context.read<MusicService>().coverExists(track.coverPath);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1DB954).withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1DB954).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          _Cover(
              coverPath: track.coverPath,
              exists: coverExists && track.coverPath != null),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title,
                    style: const TextStyle(
                        color: Color(0xFF1DB954),
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(track.artist,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const Icon(Icons.equalizer, color: Color(0xFF1DB954), size: 20),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final int index;
  final Track track;
  const _QueueTile({super.key, required this.index, required this.track});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final coverExists =
        context.read<MusicService>().coverExists(track.coverPath);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Material(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => state.playFromQueue(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                _Cover(
                    coverPath: track.coverPath,
                    exists: coverExists && track.coverPath != null),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(track.artist,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close,
                      color: Colors.white38, size: 18),
                  onPressed: () => state.removeFromQueue(index),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child:
                        Icon(Icons.drag_handle, color: Colors.white38),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final String? coverPath;
  final bool exists;
  const _Cover({required this.coverPath, required this.exists});

  @override
  Widget build(BuildContext context) {
    if (exists && coverPath != null) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          image: DecorationImage(
            image: coverImageProvider(context,
                path: coverPath!, width: 44, height: 44),
            fit: BoxFit.cover,
            onError: (_, __) {},
          ),
        ),
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF3E3E3E),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.music_note, color: Colors.white54, size: 20),
    );
  }
}
