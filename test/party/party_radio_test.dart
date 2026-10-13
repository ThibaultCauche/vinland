import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/controllers/party_radio.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/party/party_models.dart';
import 'package:vinland/services/subsonic_refs.dart';

class ListSource implements PartyRadioSource {
  ListSource(this.songs, {this.fails = false});
  final List<PartySong> songs;
  final bool fails;
  int calls = 0;

  @override
  Future<List<PartySong>> similarTo(PartySong seed) async {
    calls++;
    if (fails) throw Exception('reseau coupe');
    return songs;
  }
}

PartySong song(String id, {String title = '', String artist = 'Daft Punk'}) =>
    PartySong(
        songId: id, title: title.isEmpty ? 'Titre $id' : title, artist: artist);

Track track(String id, String artist, {String title = ''}) => Track(
      id: 'navidrome_$id',
      title: title.isEmpty ? 'Titre $id' : title,
      artist: artist,
      album: '',
      duration: const Duration(minutes: 3),
      filePath: SubsonicRefs.stream(id),
    );

void main() {
  final seed = song('s0', title: 'One More Time');

  test('une source en panne ou vide passe la main a la suivante', () async {
    final broken = ListSource([], fails: true);
    final empty = ListSource([]);
    final good = ListSource([song('a')]);
    final radio = PartyRadio([broken, empty, good], random: Random(1));
    expect((await radio.next(seed, {}))?.songId, 'a');
    expect([broken.calls, empty.calls, good.calls], [1, 1, 1]);
  });

  test(
      'le titre en cours, ceux deja passes et leurs doublons sous un autre id '
      'sont ecartes', () async {
    final radio = PartyRadio([
      ListSource([
        song('s0'),
        song('deja'),
        // Meme morceau sur une compilation : autre id, meme titre.
        song('compil', title: 'One More Time (Radio Edit)'),
        song('neuf'),
      ]),
    ], random: Random(1));
    expect((await radio.next(seed, {'deja'}))?.songId, 'neuf');
  });

  test('aucun titre neuf nulle part : pas de radio', () async {
    final radio = PartyRadio([
      ListSource([song('deja')])
    ]);
    expect(await radio.next(seed, {'deja'}), isNull);
  });

  test('le tirage reste parmi les plus proches', () async {
    final songs = [for (var i = 0; i < 20; i++) song('t$i')];
    final radio = PartyRadio([ListSource(songs)], random: Random(7));
    for (var i = 0; i < 30; i++) {
      final picked = await radio.next(seed, {});
      expect(songs.indexWhere((s) => s.songId == picked!.songId),
          lessThan(PartyRadio.pickAmong));
    }
  });

  test(
      'artistes proches de Deezer : seuls les titres presents dans la '
      'bibliotheque sont proposes', () async {
    final library = [
      track('1', 'The Chemical Brothers'),
      track('2', 'Justice'),
      track('3', 'Céline Dion'),
      track('4', 'Daft Punk'),
    ];
    final source = RelatedArtistsRadioSource(
      relatedArtists: (artist) async =>
          artist == 'Daft Punk' ? ['Chemical Brothers', 'Justice', 'Air'] : [],
      library: () => library,
    );
    final songs = await source.similarTo(seed);
    expect(songs.map((s) => s.songId), ['1', '2']);
  });

  test("dernier recours : un autre titre du meme artiste", () async {
    final source = SameArtistRadioSource(() => [
          track('1', 'Daft Punk'),
          track('2', 'Justice'),
          Track(
            id: 'local_1',
            title: 'Démo',
            artist: 'Daft Punk',
            album: '',
            duration: Duration.zero,
            filePath: '/musique/demo.mp3',
          ),
        ]);
    final songs = await source.similarTo(seed);
    expect(songs.map((s) => s.songId), ['1'],
        reason: 'un fichier local ne peut pas etre lu par les invites');
  });

  test('titres similaires de Navidrome convertis pour la soiree', () async {
    final source = NavidromeRadioSource(
        (id) async => id == 's0' ? [track('x', 'Justice')] : []);
    final songs = await source.similarTo(seed);
    expect(songs.single.songId, 'x');
    expect(songs.single.artist, 'Justice');
  });
}
