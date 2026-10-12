import 'dart:math';

import '../models/track.dart';
import '../services/matching_service.dart';
import '../services/party/party_models.dart';
import 'party_host_dj.dart';

/// Une facon de trouver des titres proches d'un titre, tous presents sur le
/// NAS (sinon l'hote ne pourrait pas les jouer).
abstract class PartyRadioSource {
  Future<List<PartySong>> similarTo(PartySong seed);
}

/// Radio automatique du mode Soiree : quand plus personne ne propose rien
/// et que la file de l'hote est vide, elle enchaine sur un titre proche du
/// dernier joue plutot que de laisser un silence. Les sources sont
/// essayees dans l'ordre (la plus precise d'abord) ; un titre deja passe
/// dans la soiree n'est jamais repris.
class PartyRadio {
  PartyRadio(this.sources, {Random? random}) : _random = random ?? Random();

  final List<PartyRadioSource> sources;
  final Random _random;

  /// Nombre de candidats parmi lesquels on tire au sort : les premiers sont
  /// les plus proches, mais toujours prendre le premier ferait tourner la
  /// soiree en rond entre deux artistes.
  static const pickAmong = 5;

  /// Titre a enchainer apres [seed], ou null si aucune source n'a rien de
  /// neuf. [avoid] : songId deja joues ou en attente dans la soiree.
  Future<PartySong?> next(PartySong seed, Set<String> avoid) async {
    final seen = <String>{};
    for (final source in sources) {
      List<PartySong> songs;
      try {
        songs = await source.similarTo(seed);
      } catch (_) {
        // Reseau coupe, Deezer injoignable... : la source suivante.
        continue;
      }
      final candidates = <PartySong>[];
      for (final song in songs) {
        if (song.songId.isEmpty ||
            song.songId == seed.songId ||
            avoid.contains(song.songId)) {
          continue;
        }
        // Meme morceau sous un autre id (album + compilation) : compte
        // comme deja passe.
        final key = _songKey(song);
        if (key == _songKey(seed) || !seen.add(key)) continue;
        candidates.add(song);
      }
      if (candidates.isNotEmpty) {
        return candidates[_random.nextInt(min(pickAmong, candidates.length))];
      }
    }
    return null;
  }

  static String _songKey(PartySong song) =>
      '${MatchingService.coreArtist(song.artist)}|'
      '${MatchingService.coreTitle(song.title)}';
}

/// Titres similaires selon Navidrome (getSimilarSongs puis
/// getSimilarSongs2, voir NavidromeService.similarSongs).
class NavidromeRadioSource implements PartyRadioSource {
  NavidromeRadioSource(this._similar);

  final Future<List<Track>> Function(String songId) _similar;

  @override
  Future<List<PartySong>> similarTo(PartySong seed) async =>
      (await _similar(seed.songId))
          .map(partySongForTrack)
          .whereType<PartySong>()
          .toList();
}

/// Artistes proches selon Deezer, ramenes aux titres de la bibliotheque
/// (seuls ceux-la sont jouables) par MatchingService, qui sait que
/// « The Beatles » et « Beatles » sont le meme artiste.
class RelatedArtistsRadioSource implements PartyRadioSource {
  RelatedArtistsRadioSource({
    required this.relatedArtists,
    required this.library,
    this.perArtist = 3,
  });

  /// Noms des artistes proches de celui donne (vide si inconnu).
  final Future<List<String>> Function(String artist) relatedArtists;
  final List<Track> Function() library;
  final int perArtist;

  @override
  Future<List<PartySong>> similarTo(PartySong seed) async {
    if (seed.artist.trim().isEmpty) return const [];
    final names = await relatedArtists(seed.artist);
    if (names.isEmpty) return const [];
    final tracks = library();
    final songs = <PartySong>[];
    for (final name in names) {
      var taken = 0;
      for (final track in tracks) {
        if (taken >= perArtist) break;
        if (!MatchingService.artistsMatch(track.artist, name)) continue;
        final song = partySongForTrack(track);
        if (song == null) continue;
        songs.add(song);
        taken++;
      }
    }
    return songs;
  }
}

/// Dernier recours : d'autres titres du meme artiste dans la bibliotheque.
class SameArtistRadioSource implements PartyRadioSource {
  SameArtistRadioSource(this.library);

  final List<Track> Function() library;

  @override
  Future<List<PartySong>> similarTo(PartySong seed) async {
    if (seed.artist.trim().isEmpty) return const [];
    return library()
        .where((t) => MatchingService.artistsMatch(t.artist, seed.artist))
        .map(partySongForTrack)
        .whereType<PartySong>()
        .toList()
      ..shuffle();
  }
}
