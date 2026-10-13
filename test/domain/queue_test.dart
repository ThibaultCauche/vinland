import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/domain/queue.dart';
import 'package:vinland/models/track.dart';

import '../fakes/fake_player_engine.dart';

List<String> ids(Iterable<Track> tracks) => tracks.map((t) => t.id).toList();

void main() {
  final a = fakeTrack('a');
  final b = fakeTrack('b');
  final c = fakeTrack('c');
  final d = fakeTrack('d');
  final e = fakeTrack('e');
  final album = [a, b, c, d, e];

  late PlayQueue q;
  setUp(() => q = PlayQueue(random: Random(42)));

  group('continuesOnDisc', () {
    Track piste(String id, int? n, {String album = 'al-1', int? disc}) => Track(
          id: id,
          title: id,
          artist: 'Artiste',
          album: 'Live',
          duration: const Duration(minutes: 3),
          albumId: album,
          trackNumber: n,
          discNumber: disc,
        );

    test('piste suivante du meme album : enchainement voulu', () {
      expect(continuesOnDisc(piste('1', 4), piste('2', 5)), isTrue);
    });

    test('premiere piste du disque suivant : enchainement voulu', () {
      expect(continuesOnDisc(piste('1', 12, disc: 1), piste('2', 1, disc: 2)),
          isTrue);
    });

    test('album lu dans le desordre, autre album ou numeros inconnus : non',
        () {
      expect(continuesOnDisc(piste('1', 4), piste('2', 7)), isFalse);
      expect(continuesOnDisc(piste('1', 4), piste('2', 5, album: 'al-2')),
          isFalse);
      expect(continuesOnDisc(piste('1', null), piste('2', 5)), isFalse);
      expect(continuesOnDisc(piste('1', 5), piste('2', 4)), isFalse);
    });
  });

  group('start', () {
    test('la file contient ce qui suit le titre lance, dans l\'ordre', () {
      q.start(b, album, shuffled: false);
      expect(ids(q.upcoming), ['c', 'd', 'e']);
      expect(ids(q.sourceOrder), ['a', 'b', 'c', 'd', 'e']);
    });

    test('sans contexte, le titre seul devient le contexte et la file est vide',
        () {
      q.start(a, null, shuffled: false);
      expect(q.upcoming, isEmpty);
      expect(ids(q.sourceOrder), ['a']);
    });

    test('titre absent du contexte : file vide', () {
      q.start(a, [b, c], shuffled: false);
      expect(q.upcoming, isEmpty);
    });

    test('en aleatoire, la suite est melangee mais complete', () {
      q.start(a, album, shuffled: true);
      expect(ids(q.upcoming).toSet(), {'b', 'c', 'd', 'e'});
      expect(ids(q.sourceOrder), ids(album), reason: 'ordre d\'origine garde');
    });

    test('vide l\'historique du contexte precedent', () {
      q.start(a, album, shuffled: false);
      q.advance(a, shuffled: false);
      expect(q.hasHistory, isTrue);
      q.start(c, album, shuffled: false);
      expect(q.hasHistory, isFalse);
    });
  });

  group('advance', () {
    test('rend le titre suivant et met le titre courant dans l\'historique',
        () {
      q.start(a, album, shuffled: false);
      expect(q.advance(a, shuffled: false), b);
      expect(ids(q.history), ['a']);
      expect(ids(q.upcoming), ['c', 'd', 'e']);
    });

    test(
        'file epuisee : reboucle sur le contexte sans rejouer le titre courant',
        () {
      q.start(e, album, shuffled: false);
      expect(q.advance(e, shuffled: false), a);
      expect(ids(q.upcoming), ['b', 'c', 'd']);
    });

    test('contexte d\'un seul titre : le rejoue', () {
      q.start(a, [a], shuffled: false);
      expect(q.advance(a, shuffled: false), a);
    });

    test('rebouclage en aleatoire : melange, sans le titre courant en tete',
        () {
      q.start(e, album, shuffled: true);
      q.upcoming.clear();
      final next = q.advance(e, shuffled: true);
      expect(next, isNot(e));
      expect({next!.id, ...ids(q.upcoming)}, {'a', 'b', 'c', 'd'});
    });

    test('rien a jouer sans contexte', () {
      expect(q.advance(null, shuffled: false), isNull);
      expect(q.hasHistory, isFalse);
    });

    test('sans titre courant, rien n\'entre dans l\'historique', () {
      q.restore(upcoming: [b, c], source: album);
      expect(q.advance(null, shuffled: false), b);
      expect(q.hasHistory, isFalse);
    });

    test('l\'historique est borne a maxHistory titres', () {
      final many =
          List.generate(PlayQueue.maxHistory + 10, (i) => fakeTrack('t$i'));
      q.start(many.first, many, shuffled: false);
      var current = many.first;
      for (var i = 0; i < many.length - 1; i++) {
        current = q.advance(current, shuffled: false)!;
      }
      expect(q.history.length, PlayQueue.maxHistory);
      expect(q.history.last.id, 't${many.length - 2}');
    });
  });

  group('skipTo', () {
    test('abandonne les titres sautes sans les mettre dans l\'historique', () {
      q.start(a, album, shuffled: false);
      expect(q.skipTo(2, a), d);
      expect(ids(q.history), ['a']);
      expect(ids(q.upcoming), ['e']);
    });

    test('index hors bornes : ne fait rien', () {
      q.start(a, album, shuffled: false);
      expect(q.skipTo(-1, a), isNull);
      expect(q.skipTo(4, a), isNull);
      expect(ids(q.upcoming), ['b', 'c', 'd', 'e']);
      expect(q.hasHistory, isFalse);
    });
  });

  group('back', () {
    test('rend le dernier titre joue et remet le courant en tete de file', () {
      q.start(a, album, shuffled: false);
      final next = q.advance(a, shuffled: false);
      expect(q.back(next), a);
      expect(ids(q.upcoming), ['b', 'c', 'd', 'e']);
      expect(q.hasHistory, isFalse);
    });

    test('historique vide : null, file intacte', () {
      q.start(a, album, shuffled: false);
      expect(q.back(a), isNull);
      expect(ids(q.upcoming), ['b', 'c', 'd', 'e']);
    });
  });

  group('edition de la file', () {
    setUp(() => q.start(a, [a, b, c], shuffled: false));

    test('add ajoute a la fin, insertNext en tete', () {
      q.add(d);
      q.insertNext(e);
      expect(ids(q.upcoming), ['e', 'b', 'c', 'd']);
    });

    test('insertNext en ordre inverse place un album dans l\'ordre', () {
      for (final t in [d, e].reversed) {
        q.insertNext(t);
      }
      expect(ids(q.upcoming), ['d', 'e', 'b', 'c']);
    });

    test('removeAt retire, et ignore un index invalide', () {
      q.removeAt(0);
      q.removeAt(5);
      q.removeAt(-1);
      expect(ids(q.upcoming), ['c']);
    });

    test(
        'un titre glisse vers le bas atterrit a la place visee, pas une '
        'place au-dessus (convention onReorderItem)', () {
      q.add(d); // b c d
      q.reorder(0, 2); // b vers la fin : position finale
      expect(ids(q.upcoming), ['c', 'd', 'b']);
      q.reorder(0, 1); // c sous d
      expect(ids(q.upcoming), ['d', 'c', 'b']);
      q.reorder(2, 0);
      expect(ids(q.upcoming), ['b', 'd', 'c']);
    });

    test('les petites modifications gardent la meme liste (Selector)', () {
      final before = q.upcoming;
      q.add(d);
      q.insertNext(e);
      q.removeAt(0);
      q.reorder(0, 1);
      expect(identical(q.upcoming, before), isTrue);
    });
  });

  group('reshuffle', () {
    test(
        'activer : melange le reste du contexte, titres ajoutes gardes en tete',
        () {
      q.start(a, album, shuffled: false);
      final next = q.advance(a, shuffled: false); // b, historique [a]
      final extra = fakeTrack('ajout');
      q.add(extra);
      q.reshuffle(shuffled: true, current: next);
      expect(q.upcoming.first, extra);
      expect(ids(q.upcoming.skip(1)).toSet(), {'c', 'd', 'e'});
    });

    test('desactiver : remet l\'ordre d\'origine sans les titres deja joues',
        () {
      q.start(a, album, shuffled: true);
      final next = q.advance(a, shuffled: true)!;
      q.reshuffle(shuffled: false, current: next);
      final expected =
          ids(album).where((id) => id != 'a' && id != next.id).toList();
      expect(ids(q.upcoming), expected);
    });

    test('remplace la liste (les ecrans se reconstruisent)', () {
      q.start(a, album, shuffled: false);
      final before = q.upcoming;
      q.reshuffle(shuffled: true, current: a);
      expect(identical(q.upcoming, before), isFalse);
    });
  });

  test('replaceUpcoming remplace la file sans toucher au contexte', () {
    q.start(a, album, shuffled: false);
    q.replaceUpcoming([e, d]);
    expect(ids(q.upcoming), ['e', 'd']);
    expect(ids(q.sourceOrder), ids(album));
  });

  test('clear oublie tout', () {
    q.start(a, album, shuffled: false);
    q.advance(a, shuffled: false);
    q.clear();
    expect(q.upcoming, isEmpty);
    expect(q.sourceOrder, isEmpty);
    expect(q.hasHistory, isFalse);
  });
}
