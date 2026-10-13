import '../../models/discovered_album.dart';
import '../../models/discovered_track.dart';
import '../../models/track.dart';
import '../../services/discovery_service.dart';
import '../../services/local_track_matcher.dart';
import '../shared/screen_model.dart';

/// Page d'un album Deezer pas (entierement) sur le NAS
/// (DiscoveredAlbumScreen mobile et DesktopDiscoveredAlbumView) : tracklist
/// Deezer, chaque titre relie a son equivalent local s'il existe.
class DiscoveredAlbumModel extends ScreenModel {
  /// [album] si on l'a deja (resultat de recherche, page artiste), sinon
  /// [albumId] (historique de recherche, lien partage).
  DiscoveredAlbumModel({
    DiscoveredAlbum? album,
    int? albumId,
    required DiscoveryService discovery,
    required super.library,
    super.downloadWorker,
  })  : assert(album != null || albumId != null),
        _album = album,
        _albumId = albumId,
        _discovery = discovery {
    load();
  }

  final int? _albumId;
  final DiscoveryService _discovery;

  DiscoveredAlbum? _album;
  List<DiscoveredTrack> _tracks = [];
  bool _isLoading = true;

  DiscoveredAlbum? get album => _album;
  List<DiscoveredTrack> get tracks => _tracks;
  bool get isLoading => _isLoading;

  /// Recharge les titres (et leur statut "possede") des qu'une synchro NAS
  /// se termine : sinon un morceau tout juste telecharge n'apparaissait
  /// lisible qu'en quittant l'album puis en y revenant.
  @override
  void onSyncFinished() => load();

  @override
  Future<void> onTrackDownloaded(DiscoveredTrack track) => load();

  Future<void> load() async {
    _album ??= await _discovery.getAlbum(_albumId!);
    final album = _album;
    if (album != null) {
      final tracks = await _discovery.getAlbumTracks(album.id);
      if (isDisposed) return;
      _tracks = tracks;
    }
    _isLoading = false;
    changed();
  }

  /// Artiste affiche. Le champ "artist" de l'ALBUM Deezer vaut "Inconnu"
  /// pour certaines sorties (compilations, singles mal catalogues) meme
  /// quand les TITRES ont un artiste renseigne : on se replie alors sur le
  /// premier titre qui en a un (retour utilisateur).
  String get artistName {
    final album = _album;
    if (album == null) return '';
    if (album.artistName != 'Inconnu') return album.artistName;
    return _tracks
        .map((t) => t.artistName)
        .firstWhere((a) => a != 'Inconnu', orElse: () => album.artistName);
  }

  /// Equivalent local de chaque titre (id Deezer -> titre du NAS ou null),
  /// calcule une seule fois par appel : findLocalTrackMatch parcourt toute
  /// la bibliotheque.
  Map<int, Track?> localMatches() {
    final all = library.allTracks;
    return {for (final dt in _tracks) dt.id: findLocalTrackMatch(dt, all)};
  }

  /// Lance le telechargement de tous les titres absents du NAS, sans popup
  /// par titre (ils s'empileraient) : l'icone de chaque ligne suit l'etat.
  void downloadMissing(Iterable<DiscoveredTrack> missing,
      {required DownloadWaiter wait}) {
    for (final dt in missing) {
      downloadTrack(dt, wait: wait);
    }
  }

  /// Lit un titre deja sur le NAS.
  void play(Track local) => library.playTrack(local);
}
