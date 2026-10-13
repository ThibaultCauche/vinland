import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/controllers/party_host_dj.dart';
import 'package:vinland/controllers/party_radio.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/party/party_models.dart';

class FakeParty implements PartyDjParty {
  @override
  bool isHost = true;
  @override
  bool isInParty = true;
  @override
  List<PartyQueueItem> queueItems = [];
  @override
  String? nowPlayingSongId;
  @override
  List<String> playedSongIds = [];
  final announced = <String>[];

  @override
  void announceNowPlaying({String? itemId, PartySong? song, String? by}) =>
      announced.add(itemId != null
          ? 'item:$itemId'
          : 'song:${song?.songId}${by == null ? '' : ' par $by'}');
}

class FakePlayback implements PartyPlayback {
  @override
  bool isIdle = false;
  @override
  String? currentSongId;
  @override
  bool hasUpcoming = false;
  final played = <String>[];
  final upNext = <String?>[];

  @override
  Future<void> play(PartySong song) async {
    played.add(song.songId);
    currentSongId = song.songId;
    isIdle = false;
  }

  @override
  void setUpNext(PartySong? song) => upNext.add(song?.songId);
}

/// Source de radio scriptee : renvoie [songs] et note les graines.
class FakeRadioSource implements PartyRadioSource {
  FakeRadioSource(this.songs);
  List<PartySong> songs;
  final seeds = <String>[];

  @override
  Future<List<PartySong>> similarTo(PartySong seed) async {
    seeds.add(seed.songId);
    return songs;
  }
}

PartySong song(String id, {String artist = 'Daft Punk'}) =>
    PartySong(songId: id, title: 'Titre $id', artist: artist);

PartyQueueItem item(String id, String songId) => PartyQueueItem(
      id: id,
      song: PartySong(songId: songId, title: 'Titre $songId'),
      by: 'Lea',
      byId: 'm2',
    );

void main() {
  late FakeParty party;
  late FakePlayback playback;
  late PartyHostDj dj;

  setUp(() {
    party = FakeParty();
    playback = FakePlayback()..currentSongId = 'perso';
    dj = PartyHostDj(party, playback);
  });

  test('la tete de la file devient le prochain titre du lecteur', () {
    party.queueItems = [item('i1', 's1'), item('i2', 's2')];
    dj.sync();
    dj.sync();
    expect(playback.upNext, ['s1'], reason: 'pas de doublon a chaque sync');
  });

  test('un veto sur le prochain titre le remplace par le suivant', () {
    party.queueItems = [item('i1', 's1'), item('i2', 's2')];
    dj.sync();
    party.queueItems = [item('i2', 's2')];
    dj.sync();
    expect(playback.upNext, ['s1', 's2']);
  });

  test(
      'file videe : le titre de soiree prevu est retire, la file de '
      "l'hote reprend", () {
    party.queueItems = [item('i1', 's1')];
    dj.sync();
    party.queueItems = [];
    dj.sync();
    expect(playback.upNext, ['s1', null]);
  });

  test("lecteur a l'arret : la premiere proposition part tout de suite",
      () async {
    playback
      ..isIdle = true
      ..currentSongId = null;
    party.queueItems = [item('i1', 's1')];
    dj.sync();
    await Future<void>.delayed(Duration.zero);
    expect(playback.played, ['s1']);
  });

  test(
      'un titre de la file qui demarre est annonce par son item, et ne se '
      'reprogramme pas derriere lui-meme', () {
    party.queueItems = [item('i1', 's1'), item('i2', 's2')];
    dj.sync();
    playback.currentSongId = 's1';
    dj.onTrackStarted(const PartySong(songId: 's1', title: 'Titre s1'));
    expect(party.announced, ['item:i1']);
    // Le relais n'a pas encore retire i1 : on prepare deja i2.
    dj.sync();
    expect(playback.upNext.last, 's2');
  });

  test("un titre lance hors file par l'hote est annonce quand meme", () {
    dj.onTrackStarted(const PartySong(songId: 'x9', title: 'Perso'));
    expect(party.announced, ['song:x9']);
  });

  test('un invite ne pilote jamais le lecteur', () {
    party
      ..isHost = false
      ..queueItems = [item('i1', 's1')];
    playback.isIdle = true;
    dj.sync();
    dj.onTrackStarted(const PartySong(songId: 's1', title: 'Titre s1'));
    expect(playback.played, isEmpty);
    expect(playback.upNext, isEmpty);
    expect(party.announced, isEmpty);
  });

  test('titre de soiree absent de la bibliotheque : lu par son id Navidrome',
      () {
    final track = trackForPartySong(
      const PartySong(songId: 'tr-42', title: 'One More Time', coverId: 'al-7'),
      (_) => null,
    );
    expect(track.id, 'navidrome_tr-42');
    expect(track.subsonicId, 'tr-42');
    expect(track.coverArtId, 'al-7');
    final back = partySongForTrack(track)!;
    expect(back.songId, 'tr-42');
  });

  test('un fichier local ne peut pas etre annonce aux invites', () {
    final local = Track(
      id: 'local_1',
      title: 'Démo',
      artist: 'Moi',
      album: '',
      duration: Duration.zero,
      filePath: '/musique/demo.mp3',
    );
    expect(partySongForTrack(local), isNull);
  });

  group('radio automatique', () {
    late FakeRadioSource source;

    setUp(() {
      source = FakeRadioSource([song('r1'), song('r2')]);
      dj = PartyHostDj(party, playback,
          radio: PartyRadio([source], random: _FirstPick()));
    });

    test(
        "file de la soiree et file de l'hote vides : un titre proche est "
        'prepare pour la suite', () async {
      dj.onTrackStarted(song('s0'));
      await pumpEventQueue();
      expect(source.seeds, ['s0']);
      expect(playback.upNext, ['r1']);
    });

    test('la radio ne reprend pas un titre deja passe dans la soiree',
        () async {
      party.playedSongIds = ['r1'];
      dj.onTrackStarted(song('s0'));
      await pumpEventQueue();
      expect(playback.upNext, ['r2']);
    });

    test("la file de l'hote passe avant la radio", () async {
      playback.hasUpcoming = true;
      dj.onTrackStarted(song('s0'));
      await pumpEventQueue();
      expect(source.seeds, isEmpty);
      expect(playback.upNext, isEmpty);
    });

    test("une proposition d'invite remplace le titre de la radio", () async {
      dj.onTrackStarted(song('s0'));
      await pumpEventQueue();
      party.queueItems = [item('i1', 's1')];
      dj.sync();
      expect(playback.upNext, ['r1', 's1']);
    });

    test("la radio ne lance pas la musique a l'ouverture de la soiree",
        () async {
      playback
        ..isIdle = true
        ..currentSongId = null;
      dj.sync();
      await pumpEventQueue();
      expect(source.seeds, isEmpty);
      expect(playback.played, isEmpty);
    });

    test('le titre de la radio est annonce comme tel aux invites', () async {
      dj.onTrackStarted(song('s0'));
      await pumpEventQueue();
      playback.currentSongId = 'r1';
      dj.onTrackStarted(song('r1'));
      expect(party.announced.last, 'song:r1 par Radio');
    });

    test('radio coupee : rien ne se prepare, et le titre prevu est retire',
        () async {
      dj.onTrackStarted(song('s0'));
      await pumpEventQueue();
      dj.radioEnabled = false;
      expect(playback.upNext, ['r1', null]);
      dj.onTrackStarted(song('s1'));
      await pumpEventQueue();
      expect(source.seeds, ['s0']);
    });

    test("rien de neuf : on ne redemande pas avant le titre suivant", () async {
      source.songs = [];
      dj.onTrackStarted(song('s0'));
      await pumpEventQueue();
      dj.sync();
      dj.sync();
      await pumpEventQueue();
      expect(source.seeds, ['s0']);
    });
  });
}

/// Tirage au sort qui prend toujours le premier candidat.
class _FirstPick implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}
