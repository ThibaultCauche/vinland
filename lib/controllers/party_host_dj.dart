import 'dart:async';

import '../models/track.dart';
import '../services/party/party_models.dart';
import '../services/subsonic_refs.dart';
import 'player_controller.dart';

/// Ce que le DJ de soiree demande au lecteur de l'hote. Interface pour
/// tester [PartyHostDj] sans moteur audio.
abstract class PartyPlayback {
  /// Rien ne joue et rien n'est prevu : une proposition peut partir tout
  /// de suite. Faux pendant une pause volontaire au milieu d'un titre.
  bool get isIdle;

  /// Id Subsonic du titre en cours chez l'hote, s'il y en a un.
  String? get currentSongId;

  Future<void> play(PartySong song);

  /// Place [song] juste apres le titre en cours, a la place du titre de
  /// soiree place avant (veto, file reordonnee par les votes). Null :
  /// retire seulement ce dernier.
  void setUpNext(PartySong? song);
}

/// Fait jouer la file de la soiree sur l'appareil de l'hote : la tete de la
/// file est toujours le prochain titre du lecteur (preparation et fondu
/// enchaine compris, voir PlayerController), et chaque titre qui demarre est
/// annonce au relais, qui le retire alors de la file. Quand la file de la
/// soiree est vide, la file de l'hote reprend la main : pas de silence.
class PartyHostDj {
  PartyHostDj(this.party, this.playback);

  final PartyDjParty party;
  final PartyPlayback playback;

  String? _upNextSongId;
  bool _starting = false;

  /// Appele a chaque changement de la soiree (voir AppState).
  void sync() {
    if (!party.isHost || !party.isInParty) {
      _clearUpNext();
      return;
    }
    // Le titre qui vient de demarrer reste en tete tant que le relais n'a
    // pas traite son annonce : ne pas le reprogrammer derriere lui-meme.
    final current = playback.currentSongId;
    final items =
        party.queueItems.where((i) => i.song.songId != current).toList();
    if (items.isEmpty) {
      _clearUpNext();
      return;
    }
    final first = items.first;
    if (playback.isIdle) {
      if (_starting) return;
      _starting = true;
      _clearUpNext();
      unawaited(
          playback.play(first.song).whenComplete(() => _starting = false));
      return;
    }
    if (first.song.songId == _upNextSongId) return;
    playback.setUpNext(first.song);
    _upNextSongId = first.song.songId;
  }

  void _clearUpNext() {
    if (_upNextSongId == null) return;
    playback.setUpNext(null);
    _upNextSongId = null;
  }

  /// L'hote touche un titre de la file pour le lancer tout de suite.
  Future<void> playNow(PartyQueueItem item) => playback.play(item.song);

  /// Un titre vient de demarrer chez l'hote (voir AppState._onTrackStarted).
  void onTrackStarted(PartySong song) {
    if (!party.isHost || !party.isInParty) return;
    if (song.songId == _upNextSongId) _upNextSongId = null;
    final matches = party.queueItems.where((i) => i.song.songId == song.songId);
    if (matches.isNotEmpty) {
      party.announceNowPlaying(itemId: matches.first.id);
    } else if (party.nowPlayingSongId != song.songId) {
      // Titre lance par l'hote hors file : les invites le voient quand meme
      // en cours (et le relais refuse qu'on le repropose tout de suite).
      party.announceNowPlaying(song: song);
    }
  }
}

/// La partie de PartyController utile au DJ (testable avec un faux).
abstract class PartyDjParty {
  bool get isHost;
  bool get isInParty;
  List<PartyQueueItem> get queueItems;
  String? get nowPlayingSongId;
  void announceNowPlaying({String? itemId, PartySong? song});
}

/// Titre jouable pour une proposition : celui de la bibliotheque s'il y est
/// (likes, pochette en cache...), sinon une reference Navidrome construite
/// a partir de l'id (l'hote a toujours un compte sur ce serveur).
Track trackForPartySong(PartySong song, Track? Function(String id) find) =>
    find('navidrome_${song.songId}') ??
    Track(
      id: 'navidrome_${song.songId}',
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: Duration(milliseconds: song.durationMs),
      filePath: SubsonicRefs.stream(song.songId),
      coverPath:
          song.coverId == null ? null : SubsonicRefs.cover(song.coverId!),
    );

/// L'inverse, pour annoncer un titre lance hors file.
PartySong? partySongForTrack(Track track) {
  final id = track.subsonicId;
  if (id == null) return null;
  return PartySong(
    songId: id,
    title: track.title,
    artist: track.artist,
    album: track.album,
    durationMs: track.duration.inMilliseconds,
    coverId: track.coverArtId,
  );
}

/// [PartyPlayback] sur le vrai lecteur de l'app.
class PlayerPartyPlayback implements PartyPlayback {
  PlayerPartyPlayback({
    required PlayerController player,
    required Future<void> Function(Track track) playTrack,
    required Track? Function(String id) findTrack,
  })  : _player = player,
        _playTrack = playTrack,
        _find = findTrack;

  final PlayerController _player;
  final Future<void> Function(Track track) _playTrack;
  final Track? Function(String id) _find;
  Track? _upNext;

  @override
  bool get isIdle {
    final current = _player.currentTrack;
    if (current == null) return true;
    if (_player.isPlaying || _player.queue.isNotEmpty) return false;
    // Fin de file atteinte : le dernier titre est arrive au bout.
    final duration = _player.duration;
    return duration > Duration.zero &&
        _player.position >= duration - const Duration(seconds: 2);
  }

  @override
  String? get currentSongId => _player.currentTrack?.subsonicId;

  @override
  Future<void> play(PartySong song) {
    _upNext = null;
    return _playTrack(trackForPartySong(song, _find));
  }

  @override
  void setUpNext(PartySong? song) {
    final previous = _upNext;
    if (previous != null) {
      final index = _player.queue.indexWhere((t) => identical(t, previous));
      if (index >= 0) _player.removeFromQueue(index);
    }
    _upNext = null;
    if (song == null) return;
    final track = trackForPartySong(song, _find);
    _player.playNext(track);
    _upNext = track;
  }
}
