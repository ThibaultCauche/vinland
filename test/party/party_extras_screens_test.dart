// Extras du mode Soiree (session 18) : ecran d'ambiance, recap, pack
// hors-ligne, radio. Branches sur la vraie logique du relais en memoire.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinland/controllers/party_controller.dart';
import 'package:vinland/controllers/party_environment.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/screens/party/party_ambiance_screen.dart';
import 'package:vinland/screens/party/party_host_screen.dart';
import 'package:vinland/screens/party/party_offline_pack_screen.dart';
import 'package:vinland/screens/party/party_setup_screen.dart';
import 'package:vinland/services/party/party_models.dart';

import '../fakes/hub_party_socket.dart';

const relayUrl = 'wss://nas.test/jam';

Track track(String id) => Track(
      id: 'navidrome_$id',
      title: 'Titre $id',
      artist: 'Artiste',
      album: '',
      duration: const Duration(minutes: 3),
      filePath: 'subsonic:stream/$id',
    );

void main() {
  late InMemoryPartyRelay relay;
  late List<PartyController> controllers;
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 10, 17, 23, 30);
    relay = InMemoryPartyRelay();
    controllers = [];
  });

  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
  });

  PartyController phone() {
    final c = PartyController(connect: relay.connect, now: () => now);
    controllers.add(c);
    return c;
  }

  Widget app(PartyController party, Widget home, PartyEnvironment env) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PartyController>.value(value: party),
          Provider<PartyEnvironment>.value(value: env),
        ],
        child: MaterialApp(home: home),
      );

  PartyEnvironment baseEnv({
    bool Function()? radioEnabled,
    void Function(bool)? setRadioEnabled,
    Future<String?> Function(String, List<PartyPlayed>)? saveRecap,
    Future<void> Function(BuildContext, String)? shareRecap,
    List<PartyPackPlaylist> Function()? packPlaylists,
    bool Function(List<Track>)? isOffline,
    Future<void> Function(List<Track>, void Function(double))? downloadOffline,
  }) =>
      PartyEnvironment(
        relayUrl: () => relayUrl,
        hostAuth: () => goodHostAuth,
        userName: () => 'thibault',
        playNow: (_) async {},
        radioEnabled: radioEnabled,
        setRadioEnabled: setRadioEnabled,
        saveRecap: saveRecap,
        shareRecap: shareRecap,
        packPlaylists: packPlaylists,
        isOffline: isOffline,
        downloadOffline: downloadOffline,
      );

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  Future<PartyController> hostParty() async {
    final h = phone();
    await h.create(
      relayUrl: relayUrl,
      partyName: 'Anniv',
      hostName: 'Thibault',
      auth: goodHostAuth,
    );
    return h;
  }

  Future<PartyController> guestParty(String name, String code) async {
    final g = phone();
    await g.join(relayUrl: relayUrl, code: code, name: name);
    return g;
  }

  testWidgets(
      "ecran d'ambiance : titre en cours, qui l'a propose, les 3 suivants, "
      'le code pour rejoindre, et plein ecran le temps de l affichage',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = await hostParty();
    final lea = await guestParty('Léa', h.code!);
    final tom = await guestParty('Tom', h.code!);
    for (final id in ['s1', 's2', 's3']) {
      lea.suggest(PartySong(songId: id, title: 'Titre $id'));
    }
    tom.suggest(const PartySong(songId: 's4', title: 'Titre 4'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    final fullscreen = <bool>[];
    await tester.pumpWidget(app(
      h,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PartyAmbianceScreen(
              setFullscreen: (on) async => fullscreen.add(on),
              colorsFor: (_) async => null,
            ),
          )),
          child: const Text('ouvrir'),
        ),
      ),
      baseEnv(),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(fullscreen, [true]);
    expect(find.text('La musique arrive…'), findsOneWidget);

    h.announceNowPlaying(itemId: h.queue.items.first.id);
    await flush(tester);
    expect(find.text('Titre 1'), findsOneWidget);
    expect(find.text('Proposé par Léa'), findsOneWidget);
    expect(find.text(h.code!), findsOneWidget);
    // File equitable : Tom passe avant le 2e titre de Lea ; 3 suivants.
    expect(
        find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('ambiance-next-')),
        findsNWidgets(3));
    expect(find.textContaining('Titre 4'), findsOneWidget);

    // Titre de la radio.
    h.announceNowPlaying(
        song: const PartySong(songId: 's9', title: 'Titre 9'), by: 'Radio');
    await flush(tester);
    expect(find.text('Choisi par la radio'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PartyAmbianceScreen), findsNothing);
    expect(fullscreen, [true, false]);
  });

  testWidgets(
      "fin de soiree : l'hote garde la playlist « Soirée du JJ/MM » et la "
      'partage', (tester) async {
    final h = await hostParty();
    final lea = await guestParty('Léa', h.code!);
    lea.suggest(const PartySong(songId: 's1', title: 'Titre 1'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    String? savedName;
    List<String>? savedIds;
    String? shared;
    final env = baseEnv(
      saveRecap: (name, played) async {
        savedName = name;
        savedIds = [for (final p in played) p.song.songId];
        return 'pl-1';
      },
      shareRecap: (_, id) async => shared = id,
    );
    await tester.pumpWidget(app(h, const PartyHostScreen(), env));
    await flush(tester);
    h.announceNowPlaying(itemId: h.queue.items.single.id);
    await flush(tester);
    h.announceNowPlaying(
        song: const PartySong(songId: 's7', title: 'Titre 7', artist: 'X'));
    await flush(tester);
    await h.end();
    await flush(tester);

    expect(find.text('2 titres ce soir'), findsOneWidget);
    expect(find.text("Proposé par : Léa (1), l'hôte (1)"), findsOneWidget);
    await tester.tap(find.text('Garder « Soirée du 17/10 »'));
    await flush(tester);
    expect(savedName, 'Soirée du 17/10');
    expect(savedIds, ['s1', 's7']);
    expect(find.textContaining('est dans tes playlists'), findsOneWidget);
    await tester.tap(find.text('Partager avec les invités'));
    await flush(tester);
    expect(shared, 'pl-1');
  });

  testWidgets("un invite n'a pas de recap a enregistrer", (tester) async {
    final h = await hostParty();
    final lea = await guestParty('Léa', h.code!);
    h.announceNowPlaying(song: const PartySong(songId: 's7', title: 'Titre 7'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await h.end();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpWidget(app(lea, const PartyHostScreen(),
        baseEnv(saveRecap: (_, __) async => 'x')));
    await flush(tester);
    expect(lea.played, isNotEmpty);
    expect(find.byKey(const ValueKey('party-recap')), findsNothing);
  });

  testWidgets(
      'pack hors-ligne : progression pendant le telechargement, puis '
      'playlist prete', (tester) async {
    final offline = <String>{};
    late void Function(double) report;
    final env = baseEnv(
      packPlaylists: () => [
        (id: 'p1', name: 'Soirée rock', tracks: [track('a'), track('b')]),
      ],
      isOffline: (tracks) => tracks.every((t) => offline.contains(t.id)),
      downloadOffline: (tracks, onProgress) async {
        report = onProgress;
        onProgress(0.5);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        offline.addAll(tracks.map((t) => t.id));
        onProgress(1);
      },
    );
    await tester.pumpWidget(app(phone(), const PartyOfflinePackScreen(), env));
    expect(find.text('2 titres'), findsOneWidget);
    await tester.tap(find.byTooltip('Télécharger'));
    await tester.pump();
    expect(find.text('50 %'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    report(0.75);
    await tester.pump();
    expect(find.text('75 %'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Prête hors-ligne · 2 titres'), findsOneWidget);
    expect(find.byIcon(Icons.offline_pin), findsOneWidget);
  });

  testWidgets('pack hors-ligne incomplet : on le dit', (tester) async {
    final env = baseEnv(
      packPlaylists: () => [
        (id: 'p1', name: 'Soirée rock', tracks: [track('a')]),
      ],
      isOffline: (_) => false,
      downloadOffline: (_, onProgress) async => onProgress(1),
    );
    await tester.pumpWidget(app(phone(), const PartyOfflinePackScreen(), env));
    await tester.tap(find.byTooltip('Télécharger'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Pas tout téléchargé, réessaie'), findsOneWidget);
  });

  testWidgets('la radio se coupe au lancement de la soiree', (tester) async {
    var radio = true;
    final env = baseEnv(
      radioEnabled: () => radio,
      setRadioEnabled: (v) => radio = v,
    );
    await tester.pumpWidget(app(phone(), const PartySetupScreen(), env));
    await tester.tap(find.text('Radio automatique'));
    await tester.pump();
    expect(radio, isFalse);
  });
}
