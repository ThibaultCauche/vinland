import 'package:flutter/foundation.dart';

import '../../models/album.dart';
import '../../models/discovered_album.dart';
import '../../models/discovered_track.dart';
import '../../models/recent_play.dart';
import '../../models/track.dart';
import '../../services/discovery_service.dart';
import '../../services/matching_service.dart';
import '../shared/screen_model.dart';

/// Une ligne de la tracklist d'un album : soit un titre du NAS (lisible),
/// soit un titre Deezer absent du NAS (grise, telechargeable).
class AlbumTrackItem {
  final Track? local;
  final DiscoveredTrack? discovered;
  const AlbumTrackItem.local(Track track)
      : local = track,
        discovered = null;
  const AlbumTrackItem.missing(DiscoveredTrack track)
      : local = null,
        discovered = track;
}

/// Page d'un album du NAS (AlbumScreen mobile et DesktopAlbumView) : titres
/// locaux de l'album, completes par le tracklist Deezer pour montrer ceux
/// qui manquent.
class AlbumModel extends ScreenModel {
  AlbumModel({
    required this.album,
    required DiscoveryService discovery,
    required super.library,
    super.downloadWorker,
  }) : _discovery = discovery {
    load();
  }

  final Album album;
  final DiscoveryService _discovery;

  List<DiscoveredTrack> _deezerTracks = [];

  // Reste a false le temps du tout premier chargement pour ne montrer ni
  // les titres locaux seuls ni une liste incomplete avant d'avoir la
  // reponse Deezer complete (evite le "flash" 4 titres -> 16 titres). Les
  // rechargements suivants (fin de synchro) ne le remettent pas a false :
  // le contenu deja affiche reste visible pendant la mise a jour.
  bool _hasLoadedOnce = false;
  bool get hasLoadedOnce => _hasLoadedOnce;

  @override
  void onSyncFinished() => load();

  @override
  Future<void> onTrackDownloaded(DiscoveredTrack track) => load();

  /// Cherche l'album sur Deezer et recupere son tracklist de reference.
  Future<void> load() async {
    try {
      final albums = await _discovery.searchAlbums(album.title, limit: 10);
      DiscoveredAlbum? match;
      for (final a in albums) {
        if (MatchingService.artistsMatch(a.artistName, album.artist) &&
            MatchingService.albumsMatch(a.title, album.title)) {
          match = a;
          break;
        }
      }
      if (match != null) {
        final tracks = await _discovery.getAlbumTracks(match.id);
        if (isDisposed) return;
        _deezerTracks = tracks;
      }
    } catch (e) {
      debugPrint('Deezer album tracks error: $e');
    }
    _hasLoadedOnce = true;
    changed();
  }

  /// Titres locaux de l'album, un par titre, tries par titre.
  ///
  /// Par id (album.trackIds, deja assemble par MusicService.rebuildAlbums)
  /// plutot que par similarite de nom d'album : MatchingService.albumsMatch
  /// sert a rapprocher un album local d'un resultat Deezer, pas a filtrer la
  /// bibliotheque -- un titre d'album court pouvait y matcher un album
  /// totalement different ("99" dans "99 Nights (Edition Deluxe)"), d'ou
  /// des titres d'un autre artiste en fin de liste (retour utilisateur,
  /// corrige sur mobile, reste sur desktop jusqu'ici).
  ///
  /// filterArtist ne s'applique pas ici : une fois l'album ouvert, on montre
  /// TOUS ses titres, meme ceux ou l'artiste par lequel on est arrive
  /// n'apparait qu'en featuring.
  List<Track> get localTracks {
    final ids = album.trackIds.toSet();
    final tracks = library.allTracks.where((t) => ids.contains(t.id)).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    return dedupByTitle(tracks);
  }

  /// Tracklist affichee : voir buildAlbumTrackItems.
  List<AlbumTrackItem> items(List<Track> localTracks) =>
      buildAlbumTrackItems(localTracks, _deezerTracks);

  void _recordRecent() {
    library.recordRecentPlay(RecentPlay(
      type: RecentPlayType.album,
      id: album.id,
      title: album.title,
      subtitle: album.artist,
      coverPath: album.coverPath,
      playedAt: DateTime.now(),
    ));
  }

  /// Lit [track] dans le contexte de l'album (la suite enchaine l'album).
  void play(Track track, List<Track> albumTracks) {
    _recordRecent();
    library.playTrack(track, trackList: albumTracks);
  }

  /// Lit tout l'album, dans l'ordre ou melange.
  void playAll(List<Track> albumTracks, {bool shuffle = false}) {
    if (albumTracks.isEmpty) return;
    final list = shuffle ? (List.of(albumTracks)..shuffle()) : albumTracks;
    play(list.first, list);
  }
}

/// Garde un seul titre par nom normalise (la version likee si le NAS a deux
/// fois le meme morceau dans cet album) : evite qu'un titre apparaisse deux
/// fois, une fois like et une fois non.
List<Track> dedupByTitle(List<Track> tracks) {
  final byTitle = <String, Track>{};
  for (final t in tracks) {
    final key = MatchingService.normalize(t.title);
    final existing = byTitle[key];
    if (existing == null || (!existing.isLiked && t.isLiked)) {
      byTitle[key] = t;
    }
  }
  return byTitle.values.toList();
}

/// Construit la tracklist a partir de celle de Deezer (ordre et contenu de
/// reference) : chaque titre est relie a son equivalent local s'il existe,
/// sinon il reste "manquant". Les titres locaux absents du tracklist Deezer
/// (bonus...) sont ajoutes a la suite. Sans tracklist Deezer, seulement les
/// titres locaux.
List<AlbumTrackItem> buildAlbumTrackItems(
    List<Track> localTracks, List<DiscoveredTrack> deezerTracks) {
  if (deezerTracks.isEmpty) {
    return [for (final t in localTracks) AlbumTrackItem.local(t)];
  }

  final byTitle = {
    for (final t in localTracks) MatchingService.normalize(t.title): t
  };
  final items = <AlbumTrackItem>[];
  final usedKeys = <String>{};

  for (final dt in deezerTracks) {
    final match = byTitle[MatchingService.normalize(dt.title)] ??
        localTracks.cast<Track?>().firstWhere(
              (t) => MatchingService.titlesMatch(t!.title, dt.title),
              orElse: () => null,
            );
    if (match != null) {
      usedKeys.add(MatchingService.normalize(match.title));
      items.add(AlbumTrackItem.local(match));
    } else {
      items.add(AlbumTrackItem.missing(dt));
    }
  }

  for (final t in localTracks) {
    if (!usedKeys.contains(MatchingService.normalize(t.title))) {
      items.add(AlbumTrackItem.local(t));
    }
  }
  return items;
}
