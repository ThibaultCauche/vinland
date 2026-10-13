import 'dart:async';

import '../../models/album.dart';
import '../../models/discovered_album.dart';
import '../../models/discovered_artist.dart';
import '../../models/discovered_track.dart';
import '../../models/recent_play.dart';
import '../../models/track.dart';
import '../../services/artist_discography.dart';
import '../../services/discovery_service.dart';
import '../../services/matching_service.dart';
import '../shared/screen_model.dart';

/// Un titre populaire Deezer, avec son equivalent local s'il est sur le NAS.
class PopularTrack {
  final DiscoveredTrack discovered;
  final Track? local;
  const PopularTrack({required this.discovered, this.local});
}

/// Titres et albums locaux d'un artiste.
typedef ArtistLibrary = ({List<Track> tracks, List<Album> albums});

/// Page artiste (ArtistScreen mobile et DesktopArtistView) : recherche
/// Deezer, titres populaires recroises avec le NAS, albums locaux et Deezer
/// fusionnes et tries, verification "possede" en tache de fond.
class ArtistModel extends ScreenModel {
  /// [deepMatchLimit] : nombre d'albums (dans l'ordre d'affichage) dont le
  /// statut "possede" est verifie titre par titre. Le mobile n'en montre
  /// que 4 et verifie les 12 premiers (marge pour les albums qui changent
  /// de place pendant la verification) ; null = toute la discographie.
  ArtistModel({
    required this.artistName,
    required DiscoveryService discovery,
    required super.library,
    super.downloadWorker,
    this.deepMatchLimit,
  }) : _discovery = discovery {
    final cached = _discovery.artistPages[_cacheKey];
    if (cached != null) {
      _artist = cached.artist;
      _albums = cached.albums;
      _topTracks = cached.topTracks;
      _loading = false;
      if (!cached.deepMatched) _deepMatchAlbums();
      _loadTrueTrackCounts();
    } else {
      load();
    }
  }

  final String artistName;
  final int? deepMatchLimit;
  final DiscoveryService _discovery;

  DiscoveredArtist? _artist;
  List<DiscoveredAlbum> _albums = [];
  List<DiscoveredTrack> _topTracks = [];
  bool _loading = true;
  bool _deepMatching = false;
  int _deepMatchProgress = 0;
  int _deepMatchTotal = 0;

  // Nombre de titres reel par album Deezer (id -> nb_tracks) : l'endpoint
  // liste des albums d'un artiste ne renvoie pas ce champ (contrairement a
  // /album/{id}), donc on le recupere a part pour ne pas afficher le nombre
  // de titres deja telecharges comme total de l'album.
  final Map<int, int> _trueTrackCounts = {};

  String get _cacheKey => MatchingService.normalize(artistName);

  DiscoveredArtist? get discoveredArtist => _artist;
  List<DiscoveredAlbum> get discoveredAlbums => _albums;

  /// Recherche Deezer en cours (titres populaires et albums pas encore la).
  bool get isLoading => _loading;
  bool get isDeepMatching => _deepMatching;
  int get deepMatchProgress => _deepMatchProgress;
  int get deepMatchTotal => _deepMatchTotal;

  @override
  void onSyncFinished() => load();

  /// (Re)charge les donnees Deezer de l'artiste. Re-servi par le cache
  /// disque de DiscoveryService, donc peu couteux.
  Future<void> load() async {
    final data = await loadArtistDeezerData(_discovery, artistName);
    if (isDisposed) return;
    _artist = data.artist;
    _albums = data.albums;
    _topTracks = data.topTracks;
    _loading = false;
    changed();
    _discovery.artistPages[_cacheKey] = CachedArtistPage(
      artist: _artist,
      albums: _albums,
      topTracks: _topTracks,
    );
    unawaited(_deepMatchAlbums());
    unawaited(_loadTrueTrackCounts());
  }

  // Memoise le filtrage artiste : allTracks/albums restent la meme instance
  // de List tant que la bibliotheque n'a pas change (voir les getters de
  // music_service.dart), alors que la page se redessine souvent pendant son
  // chargement (progression du deep-match...). Sans ce cache, un gros
  // artiste rendait la page saccadee (retour utilisateur).
  List<Track>? _memoTracks;
  List<Album>? _memoAlbums;
  ArtistLibrary? _memo;

  /// Titres et albums locaux de l'artiste.
  ArtistLibrary get local {
    final allTracks = library.allTracks;
    final allAlbums = library.albums;
    if (_memo != null &&
        identical(allTracks, _memoTracks) &&
        identical(allAlbums, _memoAlbums)) {
      return _memo!;
    }
    _memoTracks = allTracks;
    _memoAlbums = allAlbums;
    return _memo = (
      tracks: tracksForArtist(allTracks, artistName),
      albums: albumsForArtist(allAlbums, allTracks, artistName),
    );
  }

  /// Titres populaires Deezer, chacun relie a son titre local s'il existe.
  /// Recalcule a chaque appel : un titre tout juste telecharge y apparait
  /// des que la bibliotheque l'a adopte.
  List<PopularTrack> get popularTracks {
    final candidates = local.tracks;
    return [
      for (final dt in _topTracks)
        PopularTrack(
          discovered: dt,
          local: candidates.cast<Track?>().firstWhere(
              (t) => MatchingService.titlesMatch(t!.title, dt.title),
              orElse: () => null),
        ),
    ];
  }

  /// Albums locaux et Deezer fusionnes, du plus recent au plus ancien.
  List<ArtistAlbumEntry> get albumEntries => buildArtistAlbumEntries(
        localAlbums: local.albums,
        discoveredAlbums: _albums,
        trueTrackCounts: _trueTrackCounts,
      );

  /// Photo Deezer de l'artiste, sinon la cover d'un de ses albums locaux.
  String? get imageUrl {
    final albums = local.albums;
    return _artist?.pictureBigUrl ??
        (albums.isNotEmpty ? albums.first.coverPath : null);
  }

  void _recordRecent() {
    library.recordRecentPlay(RecentPlay(
      type: RecentPlayType.artist,
      id: artistName,
      title: artistName,
      subtitle: 'Artiste',
      coverPath: imageUrl,
      playedAt: DateTime.now(),
    ));
  }

  /// Lit tous les titres locaux de l'artiste, dans l'ordre ou melanges.
  void playAll({bool shuffle = false}) {
    final tracks = local.tracks;
    if (tracks.isEmpty) return;
    _recordRecent();
    final list = shuffle ? (List.of(tracks)..shuffle()) : tracks;
    library.playTrack(list.first, trackList: list);
  }

  /// Lit un titre local de l'artiste (seul, ou suivi de [trackList]).
  void playLocal(Track track, {List<Track>? trackList}) {
    _recordRecent();
    library.playTrack(track, trackList: trackList);
  }

  /// Lit un titre populaire s'il est sur le NAS.
  void playPopular(PopularTrack track) {
    final local = track.local;
    if (local == null) return;
    _recordRecent();
    library.playTrack(local);
  }

  Future<void> _loadTrueTrackCounts() async {
    final targets = _albums
        .where((a) => a.isInLibrary && !_trueTrackCounts.containsKey(a.id))
        .toList();
    if (targets.isEmpty) return;

    // Une seule notification a la toute fin, pas une par lot : ce nombre
    // n'alimente qu'un petit label sur chaque carte d'album, rien qui
    // justifie de redessiner toute la page plusieurs fois pendant le
    // chargement (page saccadee sur un gros artiste, retour utilisateur).
    const batchSize = 5;
    for (var i = 0; i < targets.length; i += batchSize) {
      final batch = targets.skip(i).take(batchSize);
      await Future.wait(batch.map((a) async {
        final full = await _discovery.getAlbum(a.id);
        if (full?.nbTracks != null) _trueTrackCounts[a.id] = full!.nbTracks!;
      }));
      if (isDisposed) return;
    }
    changed();
  }

  Future<void> _deepMatchAlbums() async {
    final entries = albumEntries;
    final candidates =
        (deepMatchLimit == null ? entries : entries.take(deepMatchLimit!))
            .map((e) => e.discovered)
            .whereType<DiscoveredAlbum>()
            .toList();
    final unmatched = candidates.where((a) => !a.isInLibrary).length;
    if (unmatched == 0) {
      _markDeepMatched();
      return;
    }

    _deepMatching = true;
    _deepMatchTotal = unmatched;
    _deepMatchProgress = 0;
    changed();

    // Mise a jour progressive mais pas a chaque lot de 5 : chaque
    // notification recalcule toute la page. Throttle naif sur le temps,
    // suffisant puisque la derniere iteration force toujours une mise a
    // jour finale.
    var lastUiUpdate = DateTime.now();
    await deepMatchArtistAlbums(
      discovery: _discovery,
      discoveredAlbums: candidates,
      allLocalTracks: library.allTracks,
      artistName: artistName,
      onProgress: (completed, total) {
        final now = DateTime.now();
        if (completed >= total ||
            now.difference(lastUiUpdate) > const Duration(milliseconds: 400)) {
          lastUiUpdate = now;
          _deepMatchProgress = completed;
          changed();
        }
      },
    );
    if (isDisposed) return;
    _deepMatching = false;
    _markDeepMatched();
    changed();
  }

  void _markDeepMatched() {
    _discovery.artistPages[_cacheKey]?.deepMatched = true;
  }
}
