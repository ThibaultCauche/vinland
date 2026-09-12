import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/discovered_album.dart';
import '../models/discovered_track.dart';
import '../models/track.dart';
import '../services/discovery_service.dart';
import '../services/download_worker_service.dart';
import '../widgets/cover_image.dart';
import 'artist_screen.dart';

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

  /// Trouve la track locale correspondante à une track Deezer
  Track? _findLocalTrack(DiscoveredTrack dt) {
    final state = context.read<AppState>();
    final localTracks = state.allTracks;

    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Un champ vide (tag manquant sur le fichier local) ne doit jamais
    // "matcher" via contains('') -- en Dart toute chaine contient la chaine
    // vide, ce qui ferait correspondre n'importe quel morceau mal tague a
    // n'importe quelle recherche.
    bool looseMatch(String a, String b) {
      if (a.isEmpty || b.isEmpty) return a == b;
      return a == b || a.contains(b) || b.contains(a);
    }

    final dtArtist = norm(dt.artistName);
    final dtTitle = norm(dt.title);
    // "Inconnu" est un texte d'affichage (album Deezer manquant pour ce
    // titre), pas un vrai nom d'album -- le comparer bloquerait tout match
    // legitime.
    final dtAlbum = dt.albumName == 'Inconnu' ? null : norm(dt.albumName);

    for (final lt in localTracks) {
      final artistMatch = looseMatch(norm(lt.artist), dtArtist);
      // Egalite stricte pour le titre (pas looseMatch/contains) : "Around
      // the World" est un prefixe litteral de "Around the World (Radio
      // Edit)" une fois normalise, alors que ce sont des enregistrements
      // differents -- possede l'un ne veut pas dire que l'autre est lisible.
      // DiscoveryService.isInLibrary a deja fait un match plus fin (voir
      // discovery_service.dart) avant que ce bouton soit meme cliquable.
      final titleMatch = norm(lt.title) == dtTitle;
      final albumMatch = dtAlbum == null || looseMatch(norm(lt.album), dtAlbum);

      if (artistMatch && titleMatch && albumMatch) {
        return lt;
      }
    }
    return null;
  }

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
                        ArtistScreen(artistName: album.artistName),
                      );
                    },
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: const Color(0xFF3E3E3E),
                          backgroundImage: album.coverUrl != null
                              ? coverImageProvider(context,
                                  path: album.coverUrl!, width: 24, height: 24)
                              : null,
                          onBackgroundImageError:
                              album.coverUrl != null ? (_, __) {} : null,
                          child: album.coverUrl == null
                              ? const Icon(Icons.person,
                                  color: Colors.white54, size: 12)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          album.artistName,
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
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _DiscoveredTrackTile(
                  index: index,
                  track: displayTracks[index],
                  downloadState: _downloadStates[displayTracks[index].id],
                  showDownloadButton: _downloadWorker.isConfigured,
                  onTap: () {
                    if (displayTracks[index].isInLibrary) {
                      final localTrack = _findLocalTrack(displayTracks[index]);
                      if (localTrack != null) {
                        state.playTrack(localTrack);
                      }
                    }
                  },
                  onDownloadTap: () => _downloadTrack(displayTracks[index]),
                ),
                childCount: displayTracks.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 220)),
        ],
      ),
    );
  }
}

class _DiscoveredTrackTile extends StatelessWidget {
  final int index;
  final DiscoveredTrack track;
  final VoidCallback onTap;
  final _DownloadUiState? downloadState;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;

  const _DiscoveredTrackTile({
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
                  color: track.isInLibrary ? Colors.white54 : Colors.white38,
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
                      color: track.isInLibrary ? Colors.white : Colors.white38,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
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
                    color: Color(0xFF1DB954), size: 16),
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
