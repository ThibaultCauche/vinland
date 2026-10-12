import '../../models/discovered_artist.dart';
import '../../services/artist_discography.dart';
import '../../services/discovery_service.dart';
import '../shared/screen_model.dart';

/// Discographie complete d'un artiste (ArtistDiscographyScreen mobile et
/// DesktopArtistDiscographyView) : toutes ses sorties, locales et Deezer,
/// avec le tracklist de chacune charge par lots.
class ArtistDiscographyModel extends ScreenModel {
  ArtistDiscographyModel({
    required this.artistName,
    required DiscoveryService discovery,
    required super.library,
    super.downloadWorker,
  }) : _discovery = discovery {
    load();
  }

  final String artistName;
  final DiscoveryService _discovery;

  DiscoveredArtist? _artist;
  List<ArtistAlbumEntry> _entries = [];
  final Map<int, List<ReleaseTrack>> _tracksByEntry = {};
  bool _loading = true;

  DiscoveredArtist? get discoveredArtist => _artist;
  List<ArtistAlbumEntry> get entries => _entries;
  bool get isLoading => _loading;

  /// Tracklist de la sortie d'indice [index], null tant qu'elle charge.
  List<ReleaseTrack>? tracksOf(int index) => _tracksByEntry[index];

  Future<void> load() async {
    final data = await loadArtistDeezerData(_discovery, artistName);
    final localAlbums =
        albumsForArtist(library.albums, library.allTracks, artistName);

    // Contrairement a la page artiste (apercu de 4 albums), on verifie le
    // statut "possede" de toute la discographie.
    await deepMatchArtistAlbums(
      discovery: _discovery,
      discoveredAlbums: data.albums,
      allLocalTracks: library.allTracks,
      artistName: artistName,
    );

    final trueTrackCounts = <int, int>{};
    final withKnownCount = data.albums.where((a) => a.isInLibrary).toList();
    await Future.wait(withKnownCount.map((a) async {
      final full = await _discovery.getAlbum(a.id);
      if (full?.nbTracks != null) trueTrackCounts[a.id] = full!.nbTracks!;
    }));

    final entries = buildArtistAlbumEntries(
      localAlbums: localAlbums,
      discoveredAlbums: data.albums,
      trueTrackCounts: trueTrackCounts,
    );
    if (isDisposed) return;
    _artist = data.artist;
    _entries = entries;
    _loading = false;
    changed();

    // Tracklists par lots de 4 : la page s'affiche des que la liste des
    // sorties est connue, les titres arrivent ensuite.
    const batchSize = 4;
    final allLocalTracks = library.allTracks;
    for (var i = 0; i < entries.length; i += batchSize) {
      final end =
          (i + batchSize < entries.length) ? i + batchSize : entries.length;
      final indices = [for (var k = i; k < end; k++) k];
      final results = await Future.wait(indices.map((idx) => loadReleaseTracks(
            discovery: _discovery,
            entry: entries[idx],
            discoveredAlbums: data.albums,
            allLocalTracks: allLocalTracks,
          )));
      if (isDisposed) return;
      for (var k = 0; k < indices.length; k++) {
        _tracksByEntry[indices[k]] = results[k];
      }
      changed();
    }
  }

  /// Telecharge un titre manquant d'une sortie.
  Future<void> downloadRelease(ReleaseTrack track,
      {required DownloadWaiter wait}) async {
    final dt = track.discovered;
    if (dt == null) return;
    await downloadTrack(dt, wait: wait);
  }
}

/// Cover d'une sortie : celle du NAS, sinon la grande cover Deezer.
String? releaseCoverPath(ArtistAlbumEntry entry) =>
    entry.local?.coverPath ??
    entry.discovered?.coverBigUrl ??
    entry.discovered?.coverUrl;
