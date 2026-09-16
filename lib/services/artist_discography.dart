import '../models/album.dart';
import '../models/discovered_album.dart';
import '../models/discovered_artist.dart';
import '../models/discovered_track.dart';
import '../models/track.dart';
import 'discovery_service.dart';
import 'local_track_matcher.dart';
import 'matching_service.dart';

/// Entree unifiee (album local ou Deezer) pour le tri par date de sortie --
/// partagee entre la page artiste (apercu limite) et la page discographie
/// (liste complete), qui avaient chacune leur propre copie identique
/// (ArtistScreen/DesktopArtistView) avant cette extraction.
class ArtistAlbumEntry {
  final Album? local;
  final DiscoveredAlbum? discovered;
  final DateTime? sortDate;
  // Nombre de titres reel de l'album (cote Deezer) quand connu, pour un
  // album local qui n'est possede que partiellement -- sans ca la vignette
  // affichait le nombre de titres deja telecharges comme s'il s'agissait du
  // total de l'album.
  final int? knownTotalTrackCount;

  ArtistAlbumEntry.local(Album album, this.sortDate,
      {this.knownTotalTrackCount})
      : local = album,
        discovered = null;

  ArtistAlbumEntry.discovered(DiscoveredAlbum album, this.sortDate)
      : local = null,
        discovered = album,
        knownTotalTrackCount = null;

  int get trackCount => local != null
      ? (knownTotalTrackCount ?? local!.trackIds.length)
      : (discovered!.nbTracks ?? 2);
}

/// Parse une date Deezer ("YYYY-MM-DD" ou juste "YYYY") en DateTime.
DateTime? parseArtistReleaseDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw) ??
      DateTime.tryParse(RegExp(r'^\d{4}').stringMatch(raw) != null
          ? '${RegExp(r'^\d{4}').stringMatch(raw)}-01-01'
          : '');
}

List<Track> tracksForArtist(List<Track> allTracks, String artistName) {
  bool artistMatch(String? f) =>
      MatchingService.artistFieldContains(f, artistName);
  return allTracks.where((t) => artistMatch(t.artist)).toList();
}

/// Albums locaux dont l'artiste correspond, ou dont au moins une track
/// correspond (compilations/BO ou l'artiste de l'album lui-meme differe).
List<Album> albumsForArtist(
    List<Album> allAlbums, List<Track> allTracks, String artistName) {
  bool artistMatch(String? f) =>
      MatchingService.artistFieldContains(f, artistName);
  final tracksById = {for (final t in allTracks) t.id: t};
  return allAlbums.where((a) {
    if (artistMatch(a.artist)) return true;
    return a.trackIds.any((id) {
      final track = tracksById[id];
      return track != null && artistMatch(track.artist);
    });
  }).toList();
}

class ArtistDeezerData {
  final DiscoveredArtist? artist;
  final List<DiscoveredAlbum> albums;
  final List<DiscoveredTrack> topTracks;
  const ArtistDeezerData(
      {this.artist, required this.albums, required this.topTracks});
}

Future<ArtistDeezerData> loadArtistDeezerData(
    DiscoveryService discovery, String artistName) async {
  final artists = await discovery.searchArtists(artistName, limit: 5);
  DiscoveredArtist? match;
  for (final a in artists) {
    if (MatchingService.artistsMatch(a.name, artistName)) {
      match = a;
      break;
    }
  }
  if (match == null) return const ArtistDeezerData(albums: [], topTracks: []);

  final albumsFuture = discovery.getArtistAlbums(match.id, limit: 50);
  final topFuture = discovery.getArtistTopTracks(match.id, limit: 5);
  final results = await Future.wait([albumsFuture, topFuture]);
  return ArtistDeezerData(
    artist: match,
    albums: results[0] as List<DiscoveredAlbum>,
    topTracks: results[1] as List<DiscoveredTrack>,
  );
}

/// Confirme/infirme en tache de fond le statut "possede" (isInLibrary,
/// deja etabli par titre exact dans DiscoveryService) pour les albums Deezer
/// pas encore matches, en comparant leur tracklist complete aux titres
/// locaux de l'artiste (ratio de titres en commun).
Future<void> deepMatchArtistAlbums({
  required DiscoveryService discovery,
  required List<DiscoveredAlbum> discoveredAlbums,
  required List<Track> allLocalTracks,
  required String artistName,
  void Function(int completed, int total)? onProgress,
}) async {
  final localAlbumSignatures = <String, Set<String>>{};
  for (final t in allLocalTracks) {
    if (!MatchingService.artistsMatch(t.artist, artistName)) continue;
    final albumKey = MatchingService.normalize(t.album);
    localAlbumSignatures.putIfAbsent(albumKey, () => {}).add(t.title);
  }

  final unmatched = discoveredAlbums.where((a) => !a.isInLibrary).toList();
  if (unmatched.isEmpty) return;

  const batchSize = 5;
  var completed = 0;
  for (var i = 0; i < unmatched.length; i += batchSize) {
    final batch = unmatched.skip(i).take(batchSize);
    await Future.wait(batch.map((album) async {
      try {
        final deezerTracks = await discovery.getAlbumTracks(album.id);
        if (deezerTracks.isEmpty) return;

        for (final entry in localAlbumSignatures.entries) {
          final localTitles = entry.value;
          if (localTitles.isEmpty) continue;

          int matches = 0;
          for (final dt in deezerTracks) {
            if (localTitles
                .any((lt) => MatchingService.titlesMatch(lt, dt.title))) {
              matches++;
            }
          }

          final ratio = matches / deezerTracks.length;
          final threshold = deezerTracks.length <= 5 ? 0.20 : 0.10;
          if (ratio >= threshold) {
            album.isInLibrary = true;
            break;
          }
        }
      } catch (_) {}
    }));
    completed += batch.length;
    onProgress?.call(completed, unmatched.length);
  }
}

/// Trouve, parmi les albums Deezer de l'artiste, celui qui correspond a un
/// album LOCAL -- verifie artiste ET titre (une recherche/comparaison par
/// titre seul avait deja fusionne a tort un single avec un album sans
/// rapport d'un autre artiste partageant un titre proche, retour
/// utilisateur).
DiscoveredAlbum? findDeezerAlbumForLocal(
    List<DiscoveredAlbum> discoveredAlbums, Album local) {
  for (final d in discoveredAlbums) {
    if (MatchingService.artistsMatch(d.artistName, local.artist) &&
        MatchingService.albumsMatch(d.title, local.title)) {
      return d;
    }
  }
  return null;
}

/// Albums locaux + Deezer tries par date de sortie decroissante (les albums
/// sans date connue sont relegues a la fin).
List<ArtistAlbumEntry> buildArtistAlbumEntries({
  required List<Album> localAlbums,
  required List<DiscoveredAlbum> discoveredAlbums,
  required Map<int, int> trueTrackCounts,
}) {
  final discoveredOnly = discoveredAlbums.where((d) => !d.isInLibrary).toList();

  return <ArtistAlbumEntry>[
    for (final a in localAlbums)
      ArtistAlbumEntry.local(
        a,
        a.year != null ? DateTime(a.year!) : null,
        knownTotalTrackCount: () {
          final match = findDeezerAlbumForLocal(discoveredAlbums, a);
          if (match == null) return null;
          return trueTrackCounts[match.id] ?? match.nbTracks;
        }(),
      ),
    for (final a in discoveredOnly)
      ArtistAlbumEntry.discovered(a, parseArtistReleaseDate(a.releaseDate)),
  ]..sort((a, b) {
      final da = a.sortDate;
      final db = b.sortDate;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
}

/// Titre d'une discographie complete : soit une track Deezer (avec son
/// eventuelle correspondance locale), soit -- quand un album local n'a
/// aucune reference Deezer -- directement une track locale.
class ReleaseTrack {
  final String title;
  final String artistName;
  final Duration? duration;
  final Track? local;
  final DiscoveredTrack? discovered;
  const ReleaseTrack({
    required this.title,
    required this.artistName,
    this.duration,
    this.local,
    this.discovered,
  });
}

/// Charge le tracklist complet d'une entree de discographie : la reference
/// Deezer quand on en a une (avec statut "possede" par titre), sinon
/// simplement les titres locaux de l'album dans l'ordre connu du NAS.
Future<List<ReleaseTrack>> loadReleaseTracks({
  required DiscoveryService discovery,
  required ArtistAlbumEntry entry,
  required List<DiscoveredAlbum> discoveredAlbums,
  required List<Track> allLocalTracks,
}) async {
  DiscoveredAlbum? deezerAlbum = entry.discovered;
  if (deezerAlbum == null && entry.local != null) {
    final match = findDeezerAlbumForLocal(discoveredAlbums, entry.local!);
    final total = entry.knownTotalTrackCount ?? entry.local!.trackIds.length;
    if (match != null && total > entry.local!.trackIds.length) {
      deezerAlbum = match;
    }
  }

  if (deezerAlbum != null) {
    final deezerTracks = await discovery.getAlbumTracks(deezerAlbum.id);
    if (deezerTracks.isNotEmpty) {
      return [
        for (final dt in deezerTracks)
          ReleaseTrack(
            title: dt.title,
            artistName: dt.artistName,
            duration: dt.duration,
            local: findLocalTrackMatch(dt, allLocalTracks),
            discovered: dt,
          ),
      ];
    }
  }

  final local = entry.local;
  if (local == null) return [];
  final byId = {for (final t in allLocalTracks) t.id: t};
  return [
    for (final id in local.trackIds)
      if (byId[id] != null)
        ReleaseTrack(
          title: byId[id]!.title,
          artistName: byId[id]!.artist,
          duration: byId[id]!.duration,
          local: byId[id],
        ),
  ];
}
