import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/domain/listening_stats.dart';
import 'package:vinland/widgets/wrapped_view.dart';

import '../fakes/fake_app_state.dart';
import '../fakes/fake_screen_deps.dart';

class _WrappedAppState extends FakeAppState {
  _WrappedAppState(super.lib, this.history);
  final List<PlayEvent> history;

  @override
  Future<List<PlayEvent>> listeningHistory() async => history;
}

PlayEvent _e(String title, String artist, DateTime at) => PlayEvent(
    at: at,
    trackId: 'navidrome_$title',
    title: title,
    artist: artist,
    album: 'Album',
    genre: 'Rock',
    duration: const Duration(minutes: 3));

void main() {
  Future<void> show(WidgetTester tester, _WrappedAppState state) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(hostScreen(const WrappedView(),
        state: state, discovery: FakeDiscovery()));
    await tester.pumpAndSettle();
  }

  testWidgets('bilan de l annee : chiffres, artiste n°1 et moments forts',
      (tester) async {
    final state = _WrappedAppState(FakeLibrary(tracks: [track('t1', 'A')]), [
      _e('A', 'Muse', DateTime(2026, 3, 1)),
      _e('A', 'Muse', DateTime(2026, 3, 1)),
      _e('B', 'Air', DateTime(2026, 4, 2)),
      _e('C', 'Daft Punk', DateTime(2025, 6, 2)),
    ]);
    await show(tester, state);
    expect(find.text('Ton année 2026'), findsOneWidget);
    expect(find.text('9'), findsOneWidget); // minutes
    expect(find.text('Ton artiste n°1'), findsOneWidget);
    expect(find.text('Muse'), findsWidgets);
    expect(find.text('Ton mois le plus musical : mars'), findsOneWidget);
    expect(find.text('Ton jour record : 1 mars'), findsOneWidget);

    await tester.tap(find.text('2025'));
    await tester.pumpAndSettle();
    expect(find.text('Ton année 2025'), findsOneWidget);
    expect(find.text('Daft Punk'), findsWidgets);
  });

  testWidgets('journal vide : bilan depuis toujours, sinon message',
      (tester) async {
    await show(tester, _WrappedAppState(FakeLibrary(tracks: []), const []));
    expect(find.text('Depuis toujours'), findsOneWidget);
    expect(find.textContaining('Pas encore assez'), findsOneWidget);
  });
}
