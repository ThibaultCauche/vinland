import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/music_service.dart';

Track _track({bool isLiked = false, DateTime? dateAdded}) => Track(
      id: 'navidrome_1',
      title: 'Titre',
      artist: 'Artiste',
      album: 'Album',
      duration: const Duration(minutes: 3),
      isLiked: isLiked,
      dateAdded: dateAdded,
    );

void main() {
  group('reconcileTrack', () {
    test(
        'ne perd pas la date locale connue meme si le serveur pose une date starred differente',
        () {
      final localDate = DateTime(2026, 1, 1);
      final t = _track(dateAdded: localDate);
      final recovery = <String>{};

      reconcileTrack(
        t,
        starredMap: {t.id: DateTime(2026, 9, 1)},
        localData: {
          t.id: {'isLiked': true, 'dateAdded': localDate}
        },
        tracksNeedingOrderRecovery: recovery,
      );

      // Regression du 2026-09-13 : reconcile() ecrasait cette date locale en
      // reposant `local['dateAdded']` meme quand elle etait deja connue,
      // via `t.dateAdded = local['dateAdded'];` (sans ??) juste apres avoir
      // pose la date starred du serveur -- ce qui revenait au meme resultat
      // ici par coincidence (les deux venaient de `local`), donc le vrai
      // test est le suivant (cache local vide).
      expect(t.dateAdded, localDate);
      expect(recovery, isEmpty);
    });

    test(
        'sans cache local du tout (reinstall), reste marque a recuperer depuis le miroir plutot que de garder la date starred imprecise',
        () {
      final t = _track();
      final recovery = <String>{};

      reconcileTrack(
        t,
        starredMap: {t.id: DateTime(2026, 9, 1)},
        localData: {}, // reinstall : aucun cache local connu
        tracksNeedingOrderRecovery: recovery,
      );

      // Regression du 2026-09-14 : sans entree localData, reconcile() ne
      // marquait pas ce titre comme necessitant une recuperation d'ordre,
      // le laissant sur le timestamp "starred" imprecis/non ordonne.
      expect(t.isLiked, isTrue);
      expect(recovery, contains(t.id));
    });

    test('un titre non like par le serveur ni en local reste non like', () {
      final t = _track();
      final recovery = <String>{};

      reconcileTrack(
        t,
        starredMap: {},
        localData: {},
        tracksNeedingOrderRecovery: recovery,
      );

      expect(t.isLiked, isFalse);
      expect(recovery, isEmpty);
    });

    test('le cache local peut retirer un like que le serveur ne connait plus (unlike)', () {
      final t = _track(isLiked: true, dateAdded: DateTime(2026, 1, 1));
      final recovery = <String>{};

      reconcileTrack(
        t,
        starredMap: {}, // plus starred cote serveur
        localData: {
          t.id: {'isLiked': false, 'dateAdded': null}
        },
        tracksNeedingOrderRecovery: recovery,
      );

      expect(t.isLiked, isFalse);
      expect(recovery, isEmpty);
    });

    test('superLiked est toujours purement local, jamais deduit du serveur', () {
      final t = _track(isLiked: true);
      final recovery = <String>{};

      reconcileTrack(
        t,
        starredMap: {t.id: DateTime(2026, 1, 1)},
        localData: {
          t.id: {'isLiked': true, 'superLiked': true}
        },
        tracksNeedingOrderRecovery: recovery,
      );

      expect(t.superLiked, isTrue);
    });
  });
}
