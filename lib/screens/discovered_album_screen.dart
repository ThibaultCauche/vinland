import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/discovered_album.dart';
import '../models/discovered_track.dart';
import '../models/track.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../services/local_track_matcher.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/cover_image.dart';
import '../widgets/player/player_options_sheet.dart';
import 'artist_screen.dart';
import '../widgets/bottom_bar_reserve.dart';

enum _DownloadUiState { downloading, failed }

class DiscoveredAlbumScreen extends StatefulWidget {
  final DiscoveredAlbum? album;
  final int? albumId;
  final String? filterArtist; // ← NOUVEAU : filtre les tracks par artiste

  const DiscoveredAlbumScreen({
    super.key,
    this.album,
    this.albumId,
    this.filterArtist,
  }) : assert(album != null || albumId != null);

  factory DiscoveredAlbumScreen.fromAlbumId(int id, {String? filterArtist}) {
    return DiscoveredAlbumScreen(albumId: id, filterArtist: filterArtist);
  }

  @override
  State<DiscoveredAlbumScreen> createState() => _DiscoveredAlbumScreenState();
}

class _DiscoveredAlbumScreenState extends State<DiscoveredAlbumScreen> {
  final _discovery = DiscoveryService();
  final _downloadWorker = DownloadWorkerService();
  DiscoveredAlbum? _album;
  List<DiscoveredTrack> _tracks = [];
  bool _isLoading = true;
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

  @override
  void dispose() {
    _appState?.removeListener(_onAppStateChanged);
    super.dispose();
  }

  /// Recharge automatiquement les tracks (et leur statut isInLibrary) des
  /// qu'une synchro Navidrome se termine pendant que cet ecran est ouvert --
  /// sans ca, un morceau tout juste telecharge n'apparaissait comme lisible
  /// qu'en quittant l'album puis en y revenant.
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
      // "Inconnu" est un texte d'affichage (voir DiscoveredTrack.fromJson),
      // pas un vrai nom d'album Deezer -- ne pas l'envoyer au worker, sinon
      // le morceau atterrit dans un dossier "Inconnu" sur le NAS.
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
      // syncRecentlyAdded() ne recupere que les derniers albums (un aller-
      // retour rapide) et fusionne dans la bibliotheque locale, contrairement
      // a syncNavidrome() qui reconstruit tout depuis zero lot par lot et
      // rend temporairement injouable le reste de la bibliotheque le temps
      // d'une synchro complete (des minutes sur une grosse bibliotheque).
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

  Future<void> _load() async {
    if (widget.album != null) {
      _album = widget.album;
    } else if (widget.albumId != null) {
      _album = await _discovery.getAlbum(widget.albumId!);
    }

    if (_album != null) {
      _tracks = await _discovery.getAlbumTracks(_album!.id);
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// Vérifie si l'artiste recherché est présent dans le champ artiste
  bool _artistContains(String? artistField, String search) {
    if (artistField == null) return false;
    final s = search.toLowerCase();
    final f = artistField.toLowerCase();
    if (f == s) return true;
    if (f.contains(s)) return true;
    return f.split(RegExp(r'[/&,]')).any((p) => p.trim() == s);
  }

  /// Trouve la track locale correspondante à une track Deezer -- voir
  /// findLocalTrackMatch (partagee avec DesktopDiscoveredAlbumView cote
  /// desktop) pour la logique de matching.
  Track? _findLocalTrack(DiscoveredTrack dt) =>
      findLocalTrackMatch(dt, context.read<AppState>().allTracks);

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final album = _album;

    if (_isLoading || album == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF1DB954)),
        ),
      );
    }

    // Filtre les tracks si filterArtist est fourni
    final displayTracks = widget.filterArtist != null
        ? _tracks
            .where((t) => _artistContains(t.artistName, widget.filterArtist!))
            .toList()
        : _tracks;

    // album.artistName vient du champ "artist" de l'ALBUM cote Deezer, qui
    // est "Inconnu" pour certaines sorties (compilations, singles mal
    // catalogues...) meme quand les TITRES individuels ont, eux, un artiste
    // correctement renseigne -- repli sur le premier titre qui en a un
    // plutot que d'afficher "Inconnu" alors que l'info existe ailleurs.
    // Meme fix que DesktopDiscoveredAlbumView (retour utilisateur).
    final resolvedArtistName = album.artistName != 'Inconnu'
        ? album.artistName
        : _tracks
            .map((t) => t.artistName)
            .firstWhere((a) => a != 'Inconnu', orElse: () => album.artistName);

    // Calcule chaque match une seule fois (findLocalTrackMatch scanne toute
    // la bibliotheque locale par titre) au lieu de le refaire separement
    // pour le bouton "Telecharger" puis pour chaque ligne plus bas.
    final localMatches = {
      for (final dt in displayTracks) dt.id: _findLocalTrack(dt)
    };
    final missingTracks =
        displayTracks.where((dt) => localMatches[dt.id] == null).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => state.popOverlay(),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                        image: album.coverBigUrl != null
                            ? DecorationImage(
                                image: coverImageProvider(context,
                                    path: album.coverBigUrl!,
                                    width: 200,
                                    height: 200),
                                fit: BoxFit.cover,
                                onError: (_, __) {},
                              )
                            : null,
                        color: const Color(0xFF2A2A2A),
                      ),
                      child: album.coverBigUrl == null
                          ? const Icon(Icons.album,
                              color: Colors.white54, size: 64)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    album.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      state.pushOverlay(
                        ArtistScreen(artistName: resolvedArtistName),
                      );
                    },
                    child: Row(
                      children: [
                        // Vraie photo d'artiste (pas la cover de CET album) --
                        // meme widget que AlbumScreen/l'etagere "Artistes du
                        // moment", meme fix que DesktopDiscoveredAlbumView
                        // (retour utilisateur).
                        ArtistAvatar(
                          artistName: resolvedArtistName,
                          fallbackCoverPath: album.coverUrl,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          resolvedArtistName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Album • ${displayTracks.length} titres',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (missingTracks.isNotEmpty &&
                      _downloadWorker.isConfigured) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        for (final dt in missingTracks) {
                          _downloadTrack(dt);
                        }
                      },
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                          'Telecharger (${missingTracks.length} titre${missingTracks.length > 1 ? 's' : ''})'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = displayTracks[index];
                  final localTrack = localMatches[track.id];
                  return _DiscoveredTrackTile(
                    index: index,
                    track: track,
                    localTrack: localTrack,
                    downloadState: _downloadStates[track.id],
                    showDownloadButton: _downloadWorker.isConfigured,
                    onTap: () {
                      if (localTrack != null) state.playTrack(localTrack);
                    },
                    onDownloadTap: () => _downloadTrack(track),
                  );
                },
                childCount: displayTracks.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
              child: SizedBox(height: bottomBarReserve(context))),
        ],
      ),
    );
  }
}

class _DiscoveredTrackTile extends StatelessWidget {
  final int index;
  final DiscoveredTrack track;
  // Titre local resolu (voir _findLocalTrack) : non-null exactement quand
  // le titre est reellement lisible/likable/"..."-able. Remplace
  // track.isInLibrary (un matching separe, plus permissif -- pouvait dire
  // "disponible" pour un titre qu'aucune tracklist locale ne retrouvait
  // vraiment, ex: "Instant Crush (Drumless Edition)" affiche en blanc/
  // cliquable sans qu'aucune version drumless soit sur le NAS) comme signal
  // pour tout le style/l'etat de cette ligne, meme logique que
  // DesktopDiscoveredAlbumView._DiscoveredTrackRow.
  final Track? localTrack;
  final VoidCallback onTap;
  final _DownloadUiState? downloadState;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;

  const _DiscoveredTrackTile({
    required this.index,
    required this.track,
    required this.localTrack,
    required this.onTap,
    required this.downloadState,
    required this.showDownloadButton,
    required this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAvailable = localTrack != null;
    return InkWell(
      onTap: isAvailable ? onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: isAvailable ? Colors.white54 : Colors.white38,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: TextStyle(
                      color: isAvailable ? Colors.white : Colors.white38,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    // Le vrai tag local quand on l'a (fiable), pas le champ
                    // Deezer (peut etre "Inconnu" pour ce titre precis meme
                    // quand le titre est bien identifie/lisible).
                    localTrack?.artist ?? track.artistName,
                    style: TextStyle(
                      color: isAvailable ? Colors.white54 : Colors.white24,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isAvailable) ...[
              IconButton(
                icon: Icon(
                  localTrack!.isLiked ? Icons.favorite : Icons.favorite_border,
                  color: localTrack!.isLiked
                      ? const Color(0xFF1DB954)
                      : Colors.white54,
                  size: 18,
                ),
                onPressed: () =>
                    context.read<AppState>().toggleLike(localTrack!.id),
                splashRadius: 18,
              ),
              IconButton(
                icon: const Icon(Icons.more_vert,
                    color: Colors.white54, size: 18),
                onPressed: () => showPlayerOptions(context, localTrack!),
                splashRadius: 18,
              ),
            ] else if (downloadState == _DownloadUiState.downloading)
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
