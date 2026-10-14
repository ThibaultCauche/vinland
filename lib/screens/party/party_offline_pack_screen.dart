import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/party_environment.dart';
import 'party_widgets.dart';

/// Pack hors-ligne : l'hote telecharge a l'avance une ou plusieurs
/// playlists sur l'appareil branche a l'enceinte, pour que la soiree tienne
/// meme si la connexion au NAS flanche (Wi-Fi sature, box coupee...).
class PartyOfflinePackScreen extends StatefulWidget {
  const PartyOfflinePackScreen({super.key});

  @override
  State<PartyOfflinePackScreen> createState() => _PartyOfflinePackScreenState();
}

class _PartyOfflinePackScreenState extends State<PartyOfflinePackScreen> {
  /// Playlist en cours de telechargement (une seule a la fois : le NAS sert
  /// les fichiers un par un de toute facon) et sa progression.
  String? _downloading;
  double _progress = 0;
  final _failed = <String>{};

  Future<void> _download(
      PartyEnvironment env, PartyPackPlaylist playlist) async {
    setState(() {
      _downloading = playlist.id;
      _progress = 0;
      _failed.remove(playlist.id);
    });
    try {
      await env.downloadOffline!(playlist.tracks, (p) {
        if (mounted) setState(() => _progress = p);
      });
    } catch (e) {
      debugPrint('offline pack error: $e');
    }
    if (!mounted) return;
    setState(() {
      _downloading = null;
      if (!env.isOffline!(playlist.tracks)) _failed.add(playlist.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final env = context.read<PartyEnvironment>();
    final playlists = env.packPlaylists?.call() ?? const [];
    return PartyBackground(
        child: Scaffold(
      backgroundColor: partyBackground,
      appBar: partyAppBar('Pack hors-ligne'),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'Télécharge à l\'avance une playlist sur cet appareil : elle '
              'passera même si le réseau flanche pendant la soirée. Fais-le '
              'chez toi, en Wi-Fi.',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ),
          if (playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Crée d\'abord une playlist pour la soirée dans ta '
                'bibliothèque.',
                textAlign: TextAlign.center,
                style: partyMuted,
              ),
            ),
          for (final playlist in playlists) _tile(env, playlist),
        ],
      ),
    ));
  }

  Widget _tile(PartyEnvironment env, PartyPackPlaylist playlist) {
    final count = playlist.tracks.length;
    final ready = env.isOffline?.call(playlist.tracks) ?? false;
    final busy = _downloading == playlist.id;
    final Widget trailing;
    if (busy) {
      trailing = Text('${(_progress * 100).round()} %',
          style: const TextStyle(color: partyAccent));
    } else if (ready) {
      trailing = const Icon(Icons.offline_pin, color: Colors.greenAccent);
    } else {
      trailing = IconButton(
        tooltip: 'Télécharger',
        icon: const Icon(Icons.download_rounded, color: Colors.white),
        onPressed: _downloading == null && env.downloadOffline != null
            ? () => _download(env, playlist)
            : null,
      );
    }
    final String subtitle;
    if (busy) {
      subtitle = 'Téléchargement…';
    } else if (ready) {
      subtitle = 'Prête hors-ligne · $count titre${count > 1 ? 's' : ''}';
    } else if (_failed.contains(playlist.id)) {
      subtitle = 'Pas tout téléchargé, réessaie';
    } else {
      subtitle = '$count titre${count > 1 ? 's' : ''}';
    }
    return Column(
      key: ValueKey('pack-${playlist.id}'),
      children: [
        ListTile(
          leading: const Icon(Icons.queue_music, color: partyAccent),
          title: Text(playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white)),
          subtitle: Text(subtitle,
              style: _failed.contains(playlist.id) && !busy
                  ? const TextStyle(color: Colors.redAccent, fontSize: 13)
                  : partyMuted),
          trailing: trailing,
        ),
        if (busy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(
              value: _progress,
              color: partyAccent,
              backgroundColor: Colors.white12,
            ),
          ),
      ],
    );
  }
}
