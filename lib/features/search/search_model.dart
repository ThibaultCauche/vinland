import 'dart:async';

import '../../models/album.dart';
import '../../models/discovered_album.dart';
import '../../models/discovered_artist.dart';
import '../../models/discovered_track.dart';
import '../../models/search_history_item.dart';
import '../../models/track.dart';
import '../../services/discovery_service.dart';
import '../../services/matching_service.dart';
import '../../services/search_history_service.dart';
import '../shared/screen_model.dart';

/// Un resultat "Titres" : toujours issu de la recherche Deezer (pas
/// seulement les titres deja sur le NAS, retour utilisateur), avec un lien
/// vers le titre local quand il existe, pour la lecture directe.
class SearchTrack {
  final DiscoveredTrack discovered;
  final Track? local;
  const SearchTrack({required this.discovered, this.local});
}

/// Recherche (SearchScreen mobile et DesktopSearchView) : saisie avec
/// delai, resultats Deezer artistes/albums/titres recroises avec le NAS,
/// historique des resultats ouverts.
class SearchModel extends ScreenModel {
  /// [albumLimit] : le mobile affiche 15 albums, le desktop 12.
  SearchModel({
    required DiscoveryService discovery,
    required super.library,
    required String? userId,
    SearchHistoryService? history,
    super.downloadWorker,
    this.albumLimit = 15,
    this.debounce = const Duration(milliseconds: 400),
  })  : _discovery = discovery,
        _historyService = history ?? SearchHistoryService() {
    _historyService.setCurrentUser(userId);
    _loadHistory();
  }

  final DiscoveryService _discovery;
  final SearchHistoryService _historyService;
  final int albumLimit;
  final Duration debounce;

  Timer? _debounceTimer;
  bool _isLoading = false;
  String _query = '';
  List<SearchTrack> _tracks = [];
  List<DiscoveredArtist> _artists = [];
  List<DiscoveredAlbum> _albums = [];
  List<SearchHistoryItem> _history = [];

  bool get isLoading => _isLoading;

  /// Derniere recherche lancee ; vide = on affiche l'historique.
  String get query => _query;
  List<SearchTrack> get tracks => _tracks;
  List<DiscoveredArtist> get artists => _artists;
  List<DiscoveredAlbum> get albums => _albums;
  List<SearchHistoryItem> get history => _history;
  bool get hasResults =>
      _artists.isNotEmpty || _albums.isNotEmpty || _tracks.isNotEmpty;

  Future<void> _loadHistory() async {
    await _historyService.ensureLoaded();
    _history = _historyService.history;
    changed();
  }

  /// Texte saisi : lance la recherche apres [debounce] sans nouvelle
  /// frappe, ou vide tout de suite les resultats si le champ est vide.
  void onQueryChanged(String value) {
    _debounceTimer?.cancel();
    if (value.trim().isEmpty) {
      _query = '';
      _tracks = [];
      _artists = [];
      _albums = [];
      changed();
      return;
    }
    _debounceTimer = Timer(debounce, () => search(value));
  }

  /// Recherche Deezer, pas uniquement dans les titres deja sur le NAS :
  /// sinon un titre pas encore telecharge n'apparaissait jamais, meme tape
  /// exactement (retour utilisateur). Les albums gardent l'ordre de
  /// pertinence de Deezer (un tri par popularite d'artiste faisait sortir
  /// les albums de l'artiste le plus connu plutot que les plus pertinents).
  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;
    _isLoading = true;
    _query = query;
    changed();

    final results = await Future.wait([
      _discovery.searchArtists(query, limit: 10),
      _discovery.searchAlbums(query, limit: albumLimit),
      _discovery.searchTracks(query, limit: 15),
    ]);
    if (isDisposed) return;

    final local = library.allTracks;
    _artists = results[0] as List<DiscoveredArtist>;
    _albums = results[1] as List<DiscoveredAlbum>;
    _tracks = [
      for (final dt in results[2] as List<DiscoveredTrack>)
        SearchTrack(discovered: dt, local: findLocalSearchMatch(dt, local)),
    ];
    _isLoading = false;
    changed();
  }

  /// Un titre tout juste telecharge devient lisible dans les resultats.
  @override
  Future<void> onTrackDownloaded(DiscoveredTrack track) async {
    final i = _tracks.indexWhere((t) => t.discovered.id == track.id);
    if (i == -1) return;
    _tracks[i] = SearchTrack(
      discovered: track,
      local: findLocalSearchMatch(track, library.allTracks),
    );
  }

  /// Note l'artiste dans l'historique ; la vue ouvre ensuite sa page.
  void openArtist(DiscoveredArtist artist) {
    _historyService.addArtist(artist.name, artist.id.toString(),
        query: _query, imageUrl: artist.pictureUrl);
  }

  /// Note l'album dans l'historique et renvoie l'album du NAS de meme titre
  /// s'il existe (la vue ouvre alors la page album locale plutot que la
  /// page Deezer).
  Album? openAlbum(DiscoveredAlbum album) {
    _historyService.addAlbum(album.title, album.id.toString(), album.artistName,
        query: _query, imageUrl: album.coverUrl);
    final title = album.title.toLowerCase().trim();
    for (final a in library.albums) {
      if (a.title.toLowerCase().trim() == title) return a;
    }
    return null;
  }

  /// Note un titre local dans l'historique avant de le lire.
  Future<void> rememberTrack(Track track) => _historyService.addTrack(
        track.title,
        track.id,
        track.artist,
        query: _query,
        imageUrl: track.coverPath?.startsWith('http') == true
            ? track.coverPath
            : null,
      );

  /// Titres des resultats deja sur le NAS, dans l'ordre affiche.
  List<Track> get playableTracks => [
        for (final t in _tracks)
          if (t.local != null) t.local!
      ];

  /// Titre du NAS correspondant a une entree "titre" de l'historique.
  Track? historyTrack(SearchHistoryItem item) {
    final id = item.id;
    if (id == null) return null;
    for (final t in library.allTracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> removeFromHistory(SearchHistoryItem item) async {
    await _historyService.remove(item);
    _history = _historyService.history;
    changed();
  }

  Future<void> clearHistory() async {
    await _historyService.clear();
    _history = [];
    changed();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

/// Titre du NAS correspondant a un resultat de recherche Deezer (meme
/// artiste et titre approchant).
Track? findLocalSearchMatch(DiscoveredTrack dt, List<Track> candidates) {
  for (final t in candidates) {
    if (MatchingService.artistsMatch(t.artist, dt.artistName) &&
        MatchingService.titlesMatch(t.title, dt.title)) {
      return t;
    }
  }
  return null;
}
