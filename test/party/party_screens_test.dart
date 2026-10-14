// Ecrans du mode Soiree, branches sur la vraie logique du relais en
// memoire (voir fakes/hub_party_socket.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinland/controllers/blind_test_host.dart';
import 'package:vinland/controllers/party_controller.dart';
import 'package:vinland/controllers/party_environment.dart';
import 'package:vinland/screens/party/party_guest_screen.dart';
import 'package:vinland/screens/party/party_host_screen.dart';
import 'package:vinland/screens/party/party_join_screen.dart';
import 'package:vinland/screens/party/party_qr_screen.dart';
import 'package:vinland/screens/party/party_setup_screen.dart';
import 'package:vinland/services/party/party_link.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/party/party_models.dart';
import 'package:vinland/services/subsonic_refs.dart';

import '../fakes/hub_party_socket.dart';

class _SilentPlayback implements BlindTestPlayback {
  @override
  Future<void> playExtract(Track track, Duration from) async {}
}

const relayUrl = 'wss://nas.test/jam';

void main() {
  late InMemoryPartyRelay relay;
  late List<PartyController> controllers;
  late List<String> playedNow;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    relay = InMemoryPartyRelay();
    controllers = [];
    playedNow = [];
  });

  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
  });

  PartyController phone() {
    final c = PartyController(connect: relay.connect);
    controllers.add(c);
    return c;
  }

  PartyEnvironment env({String? user = 'thibault'}) => PartyEnvironment(
        relayUrl: () => relayUrl,
        hostAuth: () => goodHostAuth,
        userName: () => user,
        playNow: (item) async => playedNow.add(item.song.songId),
      );

  Widget app(PartyController party, Widget home, {PartyEnvironment? e}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PartyController>.value(value: party),
          Provider<PartyEnvironment>.value(value: e ?? env()),
        ],
        child: MaterialApp(home: home),
      );

  /// Laisse passer les messages du relais (microtaches) et redessine.
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  Future<PartyController> hostParty({bool votes = true}) async {
    final h = phone();
    await h.create(
      relayUrl: relayUrl,
      partyName: 'Anniv',
      hostName: 'Thibault',
      auth: goodHostAuth,
      rules: PartyRules(votesEnabled: votes),
    );
    return h;
  }

  Future<PartyController> guestParty(String name, String code) async {
    final g = phone();
    await g.join(relayUrl: relayUrl, code: code, name: name);
    return g;
  }

  testWidgets("lancer une soiree affiche le code et la file vide",
      (tester) async {
    final h = phone();
    await tester.pumpWidget(app(h, const PartySetupScreen()));
    await tester.tap(find.text('Lancer la soirée'));
    await flush(tester);
    await tester.pumpAndSettle();
    expect(find.byType(PartyHostScreen), findsOneWidget);
    expect(find.text(h.code!), findsOneWidget);
    expect(find.textContaining('Pas encore de proposition'), findsOneWidget);
    expect(h.rules.maxPendingPerGuest, 3);
  });

  testWidgets('sans serveur configure, pas de soiree et on dit pourquoi',
      (tester) async {
    final h = phone();
    final noServer = PartyEnvironment(
      relayUrl: () => null,
      hostAuth: () => null,
      userName: () => null,
      playNow: (_) async {},
    );
    await tester.pumpWidget(app(h, const PartySetupScreen(), e: noServer));
    await tester.tap(find.text('Lancer la soirée'));
    await flush(tester);
    expect(find.textContaining('Connecte-toi'), findsOneWidget);
    expect(h.phase, PartyPhase.idle);
  });

  testWidgets("l'hote voit qui a propose quoi, peut lancer ou mettre un veto",
      (tester) async {
    final h = await hostParty();
    final lea = await guestParty('Léa', h.code!);
    final tom = await guestParty('Tom', h.code!);
    lea.suggest(const PartySong(songId: 's1', title: 'Titre 1'));
    tom.suggest(const PartySong(songId: 's2', title: 'Titre 2'));
    await tester.pumpWidget(app(h, const PartyHostScreen()));
    await flush(tester);

    expect(find.text('Titre 1'), findsOneWidget);
    expect(find.textContaining('proposé par Léa'), findsOneWidget);
    expect(find.textContaining('proposé par Tom'), findsOneWidget);
    expect(find.text('Invités (2)'), findsOneWidget);

    await tester.tap(find.byTooltip('Jouer maintenant').first);
    expect(playedNow, ['s1']);

    await tester.tap(find.byTooltip('Retirer (veto)').last);
    await flush(tester);
    expect(find.text('Titre 2'), findsNothing);
    expect(lea.queue.items.map((i) => i.song.title), ['Titre 1']);

    await tester.tap(find.text('Invités (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Léa'), findsOneWidget);
    expect(find.text('Tom'), findsOneWidget);

    // Exclure Tom.
    await tester.tap(find.byTooltip('Retirer ou exclure').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exclure'));
    await flush(tester);
    await tester.pumpAndSettle();
    expect(tom.endReason, PartyEndReason.banned);
    expect(find.text('Tom'), findsNothing);
  });

  testWidgets('QR code plein ecran avec le code en gros', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PartyQrScreen(
        invite: PartyInvite(relayUrl: relayUrl, code: 'K7QX2M'),
        partyName: 'Anniv',
      ),
    ));
    expect(find.text('K7QX2M'), findsOneWidget);
    expect(find.text('Anniv'), findsOneWidget);
  });

  testWidgets('invite : code faux refuse sans meme demander au relais',
      (tester) async {
    final g = phone();
    await tester.pumpWidget(app(g, const PartyJoinScreen()));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('party-code-field')), 'AB1');
    await tester.tap(find.text('Entrer'));
    await tester.pump();
    expect(find.textContaining('6 caractères'), findsOneWidget);
    expect(relay.sockets, isEmpty);
  });

  testWidgets('invite : entre avec le QR, cherche, propose et vote',
      (tester) async {
    final h = await hostParty();
    final lea = await guestParty('Léa', h.code!);
    lea.suggest(const PartySong(songId: 's5', title: 'Titre 5'));

    final zoe = phone();
    await tester.pumpWidget(app(
      zoe,
      PartyJoinScreen(invite: PartyInvite(relayUrl: relayUrl, code: h.code!)),
      e: env(user: null),
    ));
    await tester.pump();
    expect(find.text(h.code!), findsOneWidget, reason: 'code du QR pre-rempli');
    await tester.enterText(
        find.byKey(const ValueKey('party-name-field')), 'Zoé');
    await tester.tap(find.text('Entrer'));
    await flush(tester);
    await tester.pumpAndSettle();
    expect(find.byType(PartyGuestScreen), findsOneWidget);
    expect(find.text('Titre 5'), findsOneWidget);
    expect(find.textContaining('proposé par Léa'), findsOneWidget);

    // Vote pour le titre de Lea.
    await tester.tap(find.byTooltip("J'aime"));
    await flush(tester);
    expect(h.queue.items.single.score, 1);

    // Onglet Proposer : recherche puis proposition.
    await tester.tap(find.text('Proposer'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('party-search-field')), 'titre 1');
    await tester.pump(const Duration(milliseconds: 500));
    await flush(tester);
    expect(find.byKey(const ValueKey('party-result-s12')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('party-result-s12')));
    await flush(tester);
    expect(h.queue.items.map((i) => i.song.title), contains('Titre 12'));
    expect(find.text('Titre proposé !'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets("votes coupes : l'invite ne voit pas les boutons de vote",
      (tester) async {
    final h = await hostParty(votes: false);
    final lea = await guestParty('Léa', h.code!);
    final tom = await guestParty('Tom', h.code!);
    lea.suggest(const PartySong(songId: 's1', title: 'Titre 1'));
    await tester.pumpWidget(app(tom, const PartyGuestScreen()));
    await flush(tester);
    expect(find.text('Titre 1'), findsOneWidget);
    expect(find.byTooltip("J'aime"), findsNothing);
  });

  testWidgets("fin de soiree par l'hote : l'invite le voit", (tester) async {
    final h = await hostParty();
    final lea = await guestParty('Léa', h.code!);
    await tester.pumpWidget(app(lea, const PartyGuestScreen()));
    await flush(tester);
    await h.end();
    await flush(tester);
    expect(find.textContaining("L'hôte a terminé la soirée"), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(lea.phase, PartyPhase.idle);
  });

  testWidgets("blind test : l'hote lance, l'invite repond et marque",
      (tester) async {
    // Ecran de telephone haut : tous les boutons sont construits.
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final h = await hostParty();
    final lea = await guestParty('Léa', h.code!);
    final game = BlindTestHost(
      relay: h,
      playback: _SilentPlayback(),
      library: () => [
        for (final (i, artist)
            in ['Muse', 'Air', 'Justice', 'Queen', 'Abba'].indexed)
          Track(
            id: 'navidrome_b$i',
            title: 'Tube $i',
            artist: artist,
            album: 'Album',
            duration: const Duration(minutes: 4),
            filePath: SubsonicRefs.stream('b$i'),
          ),
      ],
      setDjSuspended: (_) {},
    );
    addTearDown(game.dispose);
    final hostEnv = PartyEnvironment(
      relayUrl: () => relayUrl,
      hostAuth: () => goodHostAuth,
      userName: () => 'thibault',
      playNow: (item) async {},
      blindTest: game,
    );
    await tester.pumpWidget(app(h, const PartyHostScreen(), e: hostEnv));
    await flush(tester);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blind test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5'));
    await tester.tap(find.text('Lancer'));
    await flush(tester);
    expect(find.text('Première manche'), findsOneWidget);
    await tester.tap(find.text('Première manche'));
    await flush(tester);
    expect(find.text('Révéler'), findsOneWidget);
    final good = h.blindTest!.answer!;

    // Cote invite.
    await tester.pumpWidget(app(lea, const PartyGuestScreen()));
    await flush(tester);
    expect(find.text('Manche 1 sur 5'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('blindtest-choice-$good')));
    await flush(tester);
    expect(
        find.text('Réponse envoyée, attends la révélation…'), findsOneWidget);

    game.reveal();
    await flush(tester);
    expect(find.textContaining('Bravo ! +'), findsOneWidget);
    expect(find.text('Classement'), findsOneWidget);
    expect(find.text('Léa'), findsOneWidget);
  });
}
