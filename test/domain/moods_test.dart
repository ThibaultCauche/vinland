import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/domain/moods.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/subsonic_refs.dart';

Track _t(String id, String? genre) => Track(
      id: id,
      title: id,
      artist: 'Artiste',
      album: 'Album',
      duration: const Duration(minutes: 3),
      filePath: SubsonicRefs.stream(id),
      genre: genre,
    );

void main() {
  final library = [
    _t('a', 'Hip-Hop'),
    _t('b', 'Lo-Fi'),
    _t('c', 'Hard Rock'),
    _t('d', null),
    _t('e', 'Électronique'),
  ];
  Mood mood(String label) => moods.firstWhere((m) => m.label == label);
  List<String> ids(String label) =>
      tracksForMood(mood(label), library).map((t) => t.id).toList();

  test('le genre des tags, accents et tirets compris, donne le mood', () {
    expect(ids('Rap'), ['a']);
    expect(ids('Chill'), ['b']);
    expect(ids('Rock'), ['c']);
    expect(ids('Électro'), ['e']);
  });
}
