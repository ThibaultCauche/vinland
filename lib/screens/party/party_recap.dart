import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/party_controller.dart';
import '../../controllers/party_environment.dart';
import '../../services/party/party_models.dart';
import 'party_widgets.dart';

/// Recap de fin de soiree, propose a l'hote : tout ce qui est passe et qui
/// l'a propose, a garder en playlist « Soirée du JJ/MM » puis a partager
/// avec les amis (boite de reception) ou par lien.
class PartyRecapCard extends StatefulWidget {
  const PartyRecapCard({super.key, required this.party});

  final PartyController party;

  @override
  State<PartyRecapCard> createState() => _PartyRecapCardState();
}

class _PartyRecapCardState extends State<PartyRecapCard> {
  bool _saving = false;
  String? _playlistId;
  String? _error;

  Future<void> _save(PartyEnvironment env, String name) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final id = await env.saveRecap!(name, widget.party.played);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _playlistId = id;
      if (id == null) _error = "La playlist n'a pas pu être créée.";
    });
  }

  @override
  Widget build(BuildContext context) {
    final env = context.read<PartyEnvironment>();
    final played = widget.party.played;
    if (played.isEmpty || env.saveRecap == null) return const SizedBox();
    final name = partyRecapName(played.first.at);
    final comment = partyRecapComment(played);
    final saved = _playlistId;
    return Container(
      key: const ValueKey('party-recap'),
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: partySurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${played.length} titre${played.length > 1 ? 's' : ''} ce soir',
            style: const TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(comment, style: partyMuted),
          ],
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in played)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '${p.song.title} · ${p.song.artist}'
                      '${_by(p.by)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (saved == null)
            FilledButton.icon(
              onPressed: _saving ? null : () => _save(env, name),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.playlist_add),
              label: Text('Garder « $name »'),
            )
          else ...[
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.greenAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('« $name » est dans tes playlists.',
                      style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
            if (env.shareRecap != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => env.shareRecap!(context, saved),
                icon: const Icon(Icons.share),
                label: const Text('Partager avec les invités'),
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
        ],
      ),
    );
  }

  static String _by(String by) => switch (by) {
        '' => '',
        'Radio' => ' (radio)',
        _ => ' ($by)',
      };
}
