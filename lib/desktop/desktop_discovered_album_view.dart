import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/discovered_album.dart';
import '../models/discovered_track.dart';
import '../models/track.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../widgets/smooth_scroll.dart';
import '../widgets/cover_image.dart';
import 'glass.dart';

enum _DownloadUiState { downloading, failed }

/// Page album "decouvert" desktop : equivalent de DiscoveredAlbumScreen
/// (mobile) pour un album Deezer qui n'a pas de correspondance locale
/// complete -- tracklist grisee, seuls les titres presents sur le NAS sont
/// lisibles.
class DesktopDiscoveredAlbumView extends StatefulWidget {
  final DiscoveredAlbum? album;
  final int? albumId;
  final String? filterArtist;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenArtist;

  const DesktopDiscoveredAlbumView({
    super.key,
    this.album,
    this.albumId,
    this.filterArtist,
    required this.onBack,
    required this.onOpenArtist,
  }) : assert(album != null || albumId != null);

  @override
  State<DesktopDiscoveredAlbumView> createState() =>
      _DesktopDiscoveredAlbumViewState();
}

class _DesktopDiscoveredAlbumViewState
    extends State<DesktopDiscoveredAlbumView> {
  final _discovery = DiscoveryService();
  final _downloadWorker = DownloadWorkerService();
  DiscoveredAlbum? _album;
  List<DiscoveredTrack> _tracks = [];
  bool _isLoading = true;
  final _scrollController = SmoothScrollController();
  final Map<int, _DownloadUiState> _downloadStates = {};

  AppState? _appState;
  bool _wasSyncing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.read<AppState>();
    if (!identical(appState, _appState)) {
      _appState?.removeListener(_onAppStateChanged);
      _appState = appState;
      _wasSyncing = appState.isSyncing;
      appState.addListener(_onAppStateChanged);
    }
  }

  /// Voir discovered_album_screen.dart : recharge automatiquement des
  /// qu'une synchro Navidrome se termine pendant que cet ecran est ouvert.
  void _onAppStateChanged() {
    final syncing = _appState?.isSyncing ?? false;
    if (_wasSyncing && !syncing && mounted) {
      _load();
    }
    _wasSyncing = syncing;
  }

  Future<void> _downloadTrack(DiscoveredTrack track) async {
    setState(() => _downloadStates[track.id] = _DownloadUiState.downloading);

    final jobId = await _downloadWorker.requestDownload(
      artist: track.artistName,
      title: track.title,
      album: track.albumName == 'Inconnu' ? null : track.albumName,
    );
    if (jobId == null) {
      if (mounted) {
        setState(() => _downloadStates[track.id] = _DownloadUiState.failed);
      }
      return;
    }

    final status = await _downloadWorker.waitForCompletion(jobId);
    if (!mounted) return;

    if (status.state == DownloadJobState.done) {
      // Voir discovered_album_screen.dart : syncRecentlyAdded() est un
      // aller-retour rapide (juste les derniers albums), contrairement a
      // syncNavidrome() qui reconstruit toute la bibliotheque lot par lot et
      // la rend temporairement injouable le temps d'une synchro complete.
      await context.read<AppState>().syncRecentlyAdded();
      if (mounted) await _load();
      if (mounted) setState(() => _downloadStates.remove(track.id));
    } else {
      setState(() => _downloadStates[track.id] = _DownloadUiState.failed);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _appState?.removeListener(_onAppStateChanged);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.album != null) {
      _album = widget.album;
    } else if (widget.albumId != null) {
      _album = await _discovery.getAlbum(widget.albumId!);
    }
    if (_album != null) {
      _tracks = await _discovery.getAlbumTracks(_album!.id);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  bool _artistContains(String? artistField, String search) {
    if (artistField == null) return false;
    final s = search.toLowerCase();
    final f = artistField.toLowerCase();
    if (f == s) return true;
    if (f.contains(s)) return true;
    return f.split(RegExp(r'[/&,]')).any((p) => p.trim() == s);
  }

  Track? _findLocalTrack(DiscoveredTrack dt) {
    final state = context.read<AppState>();
    final localTracks = state.allTracks;

    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Voir discovered_album_screen.dart : un champ vide (tag manquant en
    // local) ne doit jamais "matcher" via contains('') -- en Dart toute
    // chaine contient la chaine vide.
    bool looseMatch(String a, String b) {
      if (a.isEmpty || b.isEmpty) return a == b;
      return a == b || a.contains(b) || b.contains(a);
    }

    final dtArtist = norm(dt.artistName);
    final dtTitle = norm(dt.title);
    final dtAlbum = dt.albumName == 'Inconnu' ? null : norm(dt.albumName);

    for (final lt in localTracks) {
      final artistMatch = looseMatch(norm(lt.artist), dtArtist);
      // Voir discovered_album_screen.dart : egalite stricte pour le titre,
      // pas de contains() (conflit sinon entre "Around the World" et ses
      // propres variantes "(Radio Edit)"/"(Motorbass Vice Mix)").
      final titleMatch = norm(lt.title) == dtTitle;
      final albumMatch = dtAlbum == null || looseMatch(norm(lt.album), dtAlbum);

      if (artistMatch && titleMatch && albumMatch) return lt;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final album = _album;

    // topInsetCompact -- meme raison que DesktopCollectionView.
    return Padding(
      padding: const EdgeInsets.only(top: DesktopGlass.topInsetCompact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassIconButton(
                  icon: Icons.arrow_back_rounded, onPressed: widget.onBack),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: (_isLoading || album == null)
                ? const Center(
                    child:
                        CircularProgressIndicator(color: DesktopGlass.accent))
                : _buildContent(context, state, album),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, AppState state, DiscoveredAlbum album) {
    final displayTracks = widget.filterArtist != null
        ? _tracks
            .where((t) => _artistContains(t.artistName, widget.filterArtist!))
            .toList()
        : _tracks;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DesktopGlass.radiusMd),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 24,
                        offset: const Offset(0, 12)),
                  ],
                  image: album.coverBigUrl != null
                      ? DecorationImage(
                          image: coverImageProvider(context,
                              path: album.coverBigUrl!,
                              width: 200,
                              height: 200),
                          fit: BoxFit.cover,
                          onError: (_, __) {})
                      : null,
                  color: const Color(0xFF2A2A2A),
                ),
                child: album.coverBigUrl == null
                    ? const Icon(Icons.album, color: Colors.white54, size: 64)
                    : null,
              ),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      album.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    DesktopHoverable(
                      onTap: () => widget.onOpenArtist(album.artistName),
                      borderRadius: BorderRadius.circular(20),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: const Color(0xFF3E3E3E),
                            backgroundImage: album.coverUrl != null
                                ? coverImageProvider(context,
                                    path: album.coverUrl!,
                                    width: 26,
                                    height: 26)
                                : null,
                            onBackgroundImageError:
                                album.coverUrl != null ? (_, __) {} : null,
                            child: album.coverUrl == null
                                ? const Icon(Icons.person,
                                    color: Colors.white54, size: 13)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            album.artistName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('Album • ${displayTracks.length} titres',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                        const SizedBox(width: 10),
                        const Icon(Icons.cloud_off,
                            color: Colors.white24, size: 12),
                        const SizedBox(width: 4),
                        const Text('Non disponible en integralite sur le NAS',
                            style:
                                TextStyle(color: Colors.white24, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _DiscoveredTrackRow(
              index: index,
              track: displayTracks[index],
              downloadState: _downloadStates[displayTracks[index].id],
              showDownloadButton: _downloadWorker.isConfigured,
              onTap: () {
                if (displayTracks[index].isInLibrary) {
                  final localTrack = _findLocalTrack(displayTracks[index]);
                  if (localTrack != null) state.playTrack(localTrack);
                }
              },
              onDownloadTap: () => _downloadTrack(displayTracks[index]),
            ),
            childCount: displayTracks.length,
          ),
        ),
        const SliverToBoxAdapter(
            child: SizedBox(height: DesktopGlass.playerBarReserve)),
      ],
    );
  }
}

class _DiscoveredTrackRow extends StatelessWidget {
  final int index;
  final DiscoveredTrack track;
  final VoidCallback onTap;
  final _DownloadUiState? downloadState;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;

  const _DiscoveredTrackRow({
    required this.index,
    required this.track,
    required this.onTap,
    required this.downloadState,
    required this.showDownloadButton,
    required this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: track.isInLibrary ? onTap : null,
      borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text('${index + 1}',
                  style: TextStyle(
                      color:
                          track.isInLibrary ? Colors.white54 : Colors.white38,
                      fontSize: 14),
                  textAlign: TextAlign.center),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    style: TextStyle(
                      color: track.isInLibrary ? Colors.white : Colors.white38,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    track.artistName,
                    style: TextStyle(
                      color:
                          track.isInLibrary ? Colors.white54 : Colors.white24,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (track.isInLibrary)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.check_circle,
                    color: DesktopGlass.accent, size: 16),
              )
            else if (downloadState == _DownloadUiState.downloading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white38,
                ),
              )
            else if (showDownloadButton)
              InkWell(
                onTap: onDownloadTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    downloadState == _DownloadUiState.failed
                        ? Icons.error_outline
                        : Icons.download_rounded,
                    color: downloadState == _DownloadUiState.failed
                        ? Colors.redAccent
                        : Colors.white54,
                    size: 18,
                  ),
                ),
              )
            else
              const Icon(Icons.cloud_off, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }
}
