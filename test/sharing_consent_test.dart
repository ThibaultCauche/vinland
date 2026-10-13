import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/services/sharing_consent.dart';
import 'package:vinland/widgets/sharing_consent_dialog.dart';

void main() {
  group('SharingConsent.fromCache', () {
    test('un nouveau compte ne partage rien tant qu\'il n\'a pas repondu', () {
      final c = SharingConsent.fromCache(null);
      expect(c.likes, isFalse);
      expect(c.recentPlays, isFalse);
      expect(c.nowPlaying, isFalse);
      expect(c.asked, isFalse);
    });

    test(
        'un cache 1.2.x garde ses partages actifs mais la question est quand meme posee',
        () {
      // Jusqu'a la 1.2.x, tout etait partage par defaut sans rien demander, et
      // le cache ne contenait les cles que si l'utilisateur avait touche
      // aux reglages.
      final c =
          SharingConsent.fromCache({'shareRecentPlaysWithFriends': false});
      expect(c.likes, isTrue);
      expect(c.recentPlays, isFalse);
      expect(c.nowPlaying, isTrue);
      expect(c.asked, isFalse);
    });

    test('une reponse deja donnee n\'est pas redemandee', () {
      final c = SharingConsent.fromCache({
        'shareLikesWithFriends': false,
        'shareRecentPlaysWithFriends': false,
        'shareNowPlayingWithFriends': true,
        'sharingConsentAsked': true,
      });
      expect(c.likes, isFalse);
      expect(c.nowPlaying, isTrue);
      expect(c.asked, isTrue);
    });
  });

  testWidgets(
      'le dialogue de consentement part du choix actuel et renvoie ce que l\'utilisateur a coche',
      (tester) async {
    SharingConsent? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showSharingConsentDialog(
              context,
              initial: const SharingConsent(
                likes: true,
                recentPlays: true,
                nowPlaying: true,
                asked: false,
              ),
            );
          },
          child: const Text('ouvrir'),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    // Pas de fermeture par un tap a cote : le choix doit etre explicite.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Ce que tes amis voient'), findsOneWidget);

    await tester.tap(find.text('Mes écoutes récentes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.likes, isTrue);
    expect(result!.recentPlays, isFalse);
    expect(result!.nowPlaying, isTrue);
    expect(result!.asked, isTrue);
  });
}
