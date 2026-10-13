import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/services/jam_service.dart';
import 'package:vinland/services/music_service.dart';
import 'package:vinland/services/navidrome_service.dart';
import 'package:vinland/services/personal_sync_secret.dart';

Map<String, dynamic> _playlist({
  required String id,
  String owner = 'thibault',
  bool public = false,
  String comment = '',
}) =>
    {
      'id': id,
      'name': 'Vinland: synchro',
      'owner': owner,
      'public': public,
      'comment': comment,
    };

void main() {
  group('synchro perso', () {
    test(
        "l'id de synchro perso ne se calcule plus a partir du seul pseudo "
        "(audit : detournable par quiconque connait le pseudo)", () {
      final a = PersonalSyncIds.fromAccountSecret('a' * 43);
      final b = PersonalSyncIds.fromAccountSecret('b' * 43);
      expect(a.sessionId, isNot(b.sessionId));
      // Le sessionId circule entre amis (mirroir "now playing") : il ne doit
      // pas reveler le secret d'hebergement.
      expect(a.hostSecret, isNot(contains(a.sessionId)));
      expect(a.sessionId, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(a.hostSecret.length, greaterThanOrEqualTo(32));
      // Deterministe : tous les appareils du compte tombent sur les memes.
      expect(
          PersonalSyncIds.fromAccountSecret('a' * 43).hostSecret, a.hostSecret);
    });

    test("le secret n'est lu que dans une playlist privee du compte", () {
      final secret = 's' * 43;
      expect(
          findPersonalSyncSecret([
            _playlist(
                id: '1',
                owner: 'ami',
                comment: '$personalSyncTagPrefix${'x' * 43}'),
            _playlist(
                id: '2',
                public: true,
                comment: '$personalSyncTagPrefix${'y' * 43}'),
            _playlist(id: '3', comment: '$personalSyncTagPrefix$secret'),
          ], 'thibault'),
          secret);
      expect(findPersonalSyncSecret([], 'thibault'), isNull);
    });

    test(
        'deux appareils qui creent leur secret en meme temps convergent vers '
        'le meme', () {
      final playlists = [
        _playlist(id: 'b', comment: '$personalSyncTagPrefix${'2' * 43}'),
        _playlist(id: 'a', comment: '$personalSyncTagPrefix${'1' * 43}'),
      ];
      expect(findPersonalSyncSecret(playlists, 'thibault'), '1' * 43);
      expect(findPersonalSyncSecret(playlists.reversed.toList(), 'thibault'),
          '1' * 43);
    });

    test(
        "la playlist qui porte le secret n'apparait pas dans les playlists "
        "de l'utilisateur", () {
      final plan = planPlaylistSync(
        [_playlist(id: 'srv-1', comment: '$personalSyncTagPrefix${'s' * 43}')],
        [],
        ignoredServerIds: {},
        collabTagPrefix: 'vinland:collab:',
      );
      expect(plan.discovered, isEmpty);
      expect(plan.toRefresh, isEmpty);
    });

    test(
        "le sondage de la synchro perso s'espace quand aucun autre appareil "
        "n'est la, sans depasser 5 min", () {
      expect(personalSyncRetryDelay(0), const Duration(seconds: 20));
      expect(personalSyncRetryDelay(1), const Duration(seconds: 20));
      expect(personalSyncRetryDelay(2), const Duration(seconds: 40));
      expect(personalSyncRetryDelay(4), const Duration(seconds: 160));
      expect(personalSyncRetryDelay(5), const Duration(minutes: 5));
      expect(personalSyncRetryDelay(100), const Duration(minutes: 5));
    });
  });

  test('un code de Jam entre amis fait 16 octets aleatoires', () {
    final jam = WebSocketJamService(NavidromeService());
    final a = jam.generateSessionId();
    expect(a.length, 22);
    expect(a, isNot(jam.generateSessionId()));
  });
}
