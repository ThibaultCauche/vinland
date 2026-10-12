import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vinland/features/shared/library_port.dart';
import 'package:vinland/models/album.dart';
import 'package:vinland/models/discovered_album.dart';
import 'package:vinland/models/discovered_artist.dart';
import 'package:vinland/models/discovered_track.dart';
import 'package:vinland/models/recent_play.dart';
import 'package:vinland/models/search_history_item.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/discovery_service.dart';
import 'package:vinland/services/download_worker_service.dart';
import 'package:vinland/services/search_history_service.dart';

/// Faux elements pour tester les view-models de lib/features/ sans NAS,
/// sans Deezer et sans lecteur audio.

Track track(String id, String title,
        {String artist = 'Daft Punk',
        String album = 'Discovery',
        bool isLiked = false}) =>
    Track(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: const Duration(minutes: 3),
      isLiked: isLiked,
    );

DiscoveredTrack deezerTrack(int id, String title,
        {String artist = 'Daft Punk', String album = 'Discovery'}) =>
    DiscoveredTrack(id: id, title: title, artistName: artist, albumName: album);

DiscoveredAlbum deezerAlbum(int id, String title,
        {String artist = 'Daft Punk',
        String? releaseDate,
        int? nbTracks,
        bool isInLibrary = false}) =>
    DiscoveredAlbum(
      id: id,
      title: title,
      artistName: artist,
      releaseDate: releaseDate,
      nbTracks: nbTracks,
      isInLibrary: isInLibrary,
    );

/// Bibliotheque NAS en memoire. [finishSync] rejoue la fin d'une synchro.
class FakeLibrary extends ChangeNotifier implements LibraryPort {
  FakeLibrary({List<Track>? tracks, List<Album>? albums})
      : allTracks = tracks ?? [],
        albums = albums ?? [];

  @override
  List<Track> allTracks;
  @override
  List<Album> albums;
  @override
  bool isSyncing = false;

  final played = <(Track, List<Track>?)>[];
  final recent = <RecentPlay>[];
  final downloaded = <String>[];

  /// Titre ajoute a la bibliotheque quand le worker l'a telecharge.
  final Map<String, Track> arrivesOnDownload = {};

  void startSync() {
    isSyncing = true;
    notifyListeners();
  }

  void finishSync() {
    isSyncing = false;
    notifyListeners();
  }

  @override
  Future<void> handleTrackDownloaded(String artist, String title) async {
    downloaded.add('$artist - $title');
    final arrived = arrivesOnDownload[title];
    if (arrived != null) allTracks = [...allTracks, arrived];
  }

  @override
  Future<void> playTrack(Track track, {List<Track>? trackList}) async {
    played.add((track, trackList));
  }

  @override
  void recordRecentPlay(RecentPlay entry) => recent.add(entry);
}

/// Deezer en memoire. Compte les appels pour verifier le cache.
class FakeDiscovery implements DiscoveryService {
  final Map<String, List<DiscoveredArtist>> artistsByQuery = {};
  final Map<String, List<DiscoveredAlbum>> albumsByQuery = {};
  final Map<String, List<DiscoveredTrack>> tracksByQuery = {};
  final Map<int, List<DiscoveredAlbum>> artistAlbums = {};
  final Map<int, List<DiscoveredTrack>> topTracks = {};
  final Map<int, List<DiscoveredTrack>> albumTracks = {};
  final Map<int, DiscoveredAlbum> albumsById = {};
  int searchArtistCalls = 0;
  int albumTrackCalls = 0;

  @override
  final Map<String, CachedArtistPage> artistPages = {};

  @override
  Future<List<DiscoveredArtist>> searchArtists(String query,
      {int limit = 10}) async {
    searchArtistCalls++;
    return artistsByQuery[query] ?? [];
  }

  @override
  Future<List<DiscoveredAlbum>> searchAlbums(String query,
          {int limit = 10}) async =>
      (albumsByQuery[query] ?? []).take(limit).toList();

  @override
  Future<List<DiscoveredTrack>> searchTracks(String query,
          {int limit = 10}) async =>
      tracksByQuery[query] ?? [];

  @override
  Future<List<DiscoveredAlbum>> getArtistAlbums(int artistId,
          {int limit = 50}) async =>
      artistAlbums[artistId] ?? [];

  @override
  Future<List<DiscoveredTrack>> getArtistTopTracks(int artistId,
          {int limit = 5}) async =>
      topTracks[artistId] ?? [];

  @override
  Future<List<DiscoveredTrack>> getAlbumTracks(int albumId) async {
    albumTrackCalls++;
    return albumTracks[albumId] ?? [];
  }

  @override
  Future<DiscoveredAlbum?> getAlbum(int albumId) async => albumsById[albumId];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Worker de telechargement du NAS : chaque demande recoit un job, sauf si
/// [unreachable].
class FakeDownloadWorker implements DownloadWorkerService {
  bool unreachable = false;
  final requests = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<String?> requestDownload(
      {required String artist, required String title, String? album}) async {
    if (unreachable) return null;
    requests.add('$artist - $title (${album ?? 'sans album'})');
    return 'job-${requests.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Attente de fin de telechargement pilotee par le test.
class ManualWait {
  final pending = <Completer<DownloadJobStatus>>[];

  Future<DownloadJobStatus> call(DownloadWorkerService worker, String jobId) {
    final c = Completer<DownloadJobStatus>();
    pending.add(c);
    return c.future;
  }

  void finish(DownloadJobState state) =>
      pending.removeAt(0).complete(DownloadJobStatus(state: state));
}

Future<DownloadJobStatus> doneAtOnce(
        DownloadWorkerService worker, String jobId) async =>
    const DownloadJobStatus(state: DownloadJobState.done);

/// Historique de recherche en memoire (le vrai ecrit un fichier).
class FakeSearchHistory implements SearchHistoryService {
  final items = <SearchHistoryItem>[];
  String? user;

  @override
  List<SearchHistoryItem> get history => List.unmodifiable(items);

  @override
  void setCurrentUser(String? userId) => user = userId;

  @override
  Future<void> ensureLoaded() async {}

  @override
  Future<void> addArtist(String name, String id,
      {String? query, String? imageUrl}) async {
    items.insert(0, SearchHistoryItem.artist(name, id, query: query));
  }

  @override
  Future<void> addAlbum(String title, String id, String artistName,
      {String? query, String? imageUrl}) async {
    items.insert(
        0, SearchHistoryItem.album(title, id, artistName, query: query));
  }

  @override
  Future<void> addTrack(String title, String id, String artistName,
      {String? query, String? imageUrl}) async {
    items.insert(
        0, SearchHistoryItem.track(title, id, artistName, query: query));
  }

  @override
  Future<void> remove(SearchHistoryItem item) async => items.remove(item);

  @override
  Future<void> clear() async => items.clear();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
