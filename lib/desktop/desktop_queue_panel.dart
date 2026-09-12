import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../widgets/cover_image.dart';
import 'glass.dart';

/// "File d'attente" desktop, façon panneau lateral Spotify : titre en cours
/// + titres a venir (AppState.queue), reordonnables par glisser-deposer.
/// Ouvert en overlay (pas dans la pile de navigation locale de
/// DesktopAppShell) pour rester accessible depuis n'importe quel ecran sans
/// avoir a faire remonter un callback jusqu'a la racine du shell.
void showQueuePanel(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'File d\'attente',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => const _QueuePanelOverlay(),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return Align(
        alignment: Alignment.centerRight,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _QueuePanelOverlay extends StatelessWidget {
  const _QueuePanelOverlay();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 24, 24, 24 + 84 + 12),
        child: SizedBox(
          width: 360,
          child: GlassPanel(
            borderRadius: BorderRadius.circular(DesktopGlass.radiusLg),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Selector<AppState, (Track?, List<Track>)>(
                selector: (_, state) => (state.currentTrack, state.queue),
                builder: (context, data, __) {
                  final (currentTrack, queue) = data;
                  final state = context.read<AppState>();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text('File d\'attente',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const Spacer(),
                          GlassIconButton(
                            icon: Icons.close,
                            size: 18,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (currentTrack != null) ...[
                        const Text('En cours de lecture',
                            style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        _QueueRow(track: currentTrack, isCurrent: true),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        'Ensuite${queue.isNotEmpty ? ' (${queue.length})' : ''}',
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Flexible(
                        child: queue.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text('Aucun titre a venir',
                                    style: TextStyle(color: Colors.white38)),
                              )
                            : ReorderableListView.builder(
                                shrinkWrap: true,
                                buildDefaultDragHandles: false,
                                itemCount: queue.length,
                                onReorder: state.reorderQueue,
                                itemBuilder: (context, i) => _QueueRow(
                                  key: ValueKey('dq-$i-${queue[i].id}'),
                                  track: queue[i],
                                  index: i,
                                ),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final Track track;
  final int? index;
  final bool isCurrent;

  const _QueueRow(
      {super.key, required this.track, this.index, this.isCurrent = false});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final path = track.coverPath;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isCurrent
            ? DesktopGlass.accent.withOpacity(0.12)
            : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
        onTap: isCurrent || index == null
            ? null
            : () => state.playFromQueue(index!),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF3E3E3E),
                borderRadius: BorderRadius.circular(4),
                image: path != null
                    ? DecorationImage(
                        image: coverImageProvider(context,
                            path: path, width: 36, height: 36),
                        fit: BoxFit.cover,
                        onError: (_, __) {},
                      )
                    : null,
              ),
              child: path == null
                  ? const Icon(Icons.music_note,
                      color: Colors.white54, size: 16)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isCurrent ? DesktopGlass.accent : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  Text(track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
            if (isCurrent)
              const Icon(Icons.equalizer, color: DesktopGlass.accent, size: 16)
            else if (index != null) ...[
              GlassIconButton(
                icon: Icons.close,
                size: 14,
                onPressed: () => state.removeFromQueue(index!),
              ),
              ReorderableDragStartListener(
                index: index!,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_handle, color: Colors.white38, size: 18),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
