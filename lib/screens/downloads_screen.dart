import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/offline_playback.dart';
import '../models/track.dart';
import '../providers/app_state.dart';
import '../services/music_service.dart';
import '../widgets/app_background.dart';
import '../widgets/app_bar_safe_area.dart';
import '../widgets/bottom_bar_reserve.dart';
import '../widgets/track_tile.dart';

const _green = Color(0xFF1DB954);

/// « Téléchargements » : tout ce qui est disponible hors connexion sur cet
/// appareil, la place prise, la qualite des prochains telechargements, le
/// mode hors-ligne force, et de quoi tout supprimer. Meme ecran sur mobile
/// (Parametres, Bibliotheque) et sur PC (menu du profil).
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const AppBarBlurBackground(),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Téléchargements',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: PlatformBackground(
        child: Consumer<AppState>(
          builder: (context, state, _) {
            final tracks = state.downloadedTracks;
            // Material transparent : les lignes (ListTile) dessinent leurs
            // effets au toucher sur le Material le plus proche, qui serait
            // sinon cache par le fond.
            return Material(
              type: MaterialType.transparency,
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding:
                        EdgeInsets.only(top: appBarSafeTopPadding(context)),
                    sliver: SliverToBoxAdapter(
                      child: _Header(state: state, tracks: tracks),
                    ),
                  ),
                  if (tracks.isEmpty)
                    const SliverToBoxAdapter(child: _EmptyHint())
                  else
                    SliverList.builder(
                      itemCount: tracks.length,
                      itemBuilder: (context, i) {
                        final track = tracks[i];
                        return TrackTile(
                          track: track,
                          isPlaying: state.currentTrack?.id == track.id,
                          onTap: () =>
                              state.playTrack(track, trackList: tracks),
                          onLike: () => state.toggleLike(track.id),
                          onMore: () =>
                              _confirmRemoveOne(context, state, track),
                        );
                      },
                    ),
                  SliverToBoxAdapter(
                    child: SizedBox(height: bottomBarReserve(context) + 24),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmRemoveOne(
      BuildContext context, AppState state, Track track) async {
    final remove = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
          title: Text('Retirer « ${track.title} » des téléchargements',
              style: const TextStyle(color: Colors.white)),
          onTap: () => Navigator.pop(ctx, true),
        ),
      ),
    );
    if (remove == true) await state.removeDownloads([track]);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.tracks});

  final AppState state;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final count = tracks.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.isServerUnreachable && !state.offlineOnly)
            const _StatusPill(
              icon: Icons.cloud_off,
              text: 'Serveur injoignable : seuls ces titres sont jouables',
            ),
          Row(
            children: [
              const Icon(Icons.download_for_offline, color: _green, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: _SizeLabel(state: state, count: count),
              ),
            ],
          ),
          if (state.isDownloadingOffline) ...[
            const SizedBox(height: 12),
            Text(
              'Téléchargement : ${state.offlineDoneCount} / '
              '${state.offlineQueuedCount}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.offlineQueuedCount == 0
                    ? null
                    : state.offlineDoneCount / state.offlineQueuedCount,
                color: _green,
                backgroundColor: Colors.white12,
                minHeight: 4,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: count == 0
                    ? null
                    : () => state.playTrack(tracks.first, trackList: tracks),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Lecture'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.black,
                  shape: const StadiumBorder(),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: count == 0 ? null : () => _shuffle(state),
                icon: const Icon(Icons.shuffle),
                label: const Text('Aléatoire'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _green,
            secondary:
                const Icon(Icons.airplanemode_active, color: Colors.white54),
            title: const Text('Mode hors-ligne',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'N\'écouter que la musique téléchargée, sans passer par le '
                'serveur (économise les données mobiles)',
                style: TextStyle(color: Colors.white54)),
            value: state.offlineOnly,
            onChanged: state.setOfflineOnly,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _green,
            secondary: const Icon(Icons.favorite_border, color: Colors.white54),
            title: const Text('Télécharger automatiquement les likes',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text(
                'Titres, albums et playlists likés disponibles hors connexion',
                style: TextStyle(color: Colors.white54)),
            value: state.autoDownloadLikes,
            onChanged: state.setAutoDownloadLikes,
          ),
          const SizedBox(height: 8),
          const Text('Qualité des téléchargements',
              style: TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 4),
          const Text(
              'Pour les prochains téléchargements. 192 kbps est un bon '
              'compromis (environ 1,5 Mo par minute).',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final kbps in MusicService.offlineBitRateChoices)
                ChoiceChip(
                  label: Text('$kbps kbps'),
                  selected: state.offlineBitRateKbps == kbps,
                  selectedColor: _green,
                  backgroundColor: const Color(0xFF2A2A2A),
                  labelStyle: TextStyle(
                    color: state.offlineBitRateKbps == kbps
                        ? Colors.black
                        : Colors.white,
                  ),
                  showCheckmark: false,
                  onSelected: (_) => state.setOfflineBitRate(kbps),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (count > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _confirmRemoveAll(context, state),
                icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                label: const Text('Tout supprimer',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ),
          if (count > 0)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('TITRES',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1)),
            ),
        ],
      ),
    );
  }

  void _shuffle(AppState state) {
    if (!state.isShuffled) state.toggleShuffle();
    final start = tracks[Random().nextInt(tracks.length)];
    state.playTrack(start, trackList: tracks);
  }

  Future<void> _confirmRemoveAll(BuildContext context, AppState state) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Tout supprimer ?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'Plus aucun titre ne sera disponible hors connexion sur cet '
            'appareil. Tes playlists et tes likes ne sont pas touchés.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tout supprimer',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) await state.removeAllDownloads();
  }
}

/// « 245 titres · 1,2 Go », la taille etant calculee sur le disque (relue
/// quand le nombre de titres change).
class _SizeLabel extends StatefulWidget {
  const _SizeLabel({required this.state, required this.count});
  final AppState state;
  final int count;

  @override
  State<_SizeLabel> createState() => _SizeLabelState();
}

class _SizeLabelState extends State<_SizeLabel> {
  Future<int>? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.state.offlineBytes();
  }

  @override
  void didUpdateWidget(covariant _SizeLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) _bytes = widget.state.offlineBytes();
  }

  @override
  Widget build(BuildContext context) {
    final titles = '${widget.count} titre${widget.count > 1 ? 's' : ''}';
    return FutureBuilder<int>(
      future: _bytes,
      builder: (context, snapshot) {
        final size =
            snapshot.hasData ? ' · ${formatBytes(snapshot.data!)}' : '';
        return Text('$titles$size',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold));
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _green, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Text(
        'Rien de téléchargé pour l\'instant. Touche la flèche ⬇ sur un '
        'album, une playlist ou tes titres likés pour les écouter sans '
        'connexion.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white54),
      ),
    );
  }
}
