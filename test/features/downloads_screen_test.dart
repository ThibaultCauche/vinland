import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinland/data/subsonic/subsonic_client.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/providers/app_state.dart';
import 'package:vinland/screens/downloads_screen.dart';
import 'package:vinland/services/music_service.dart';
import 'package:vinland/services/navidrome_service.dart';
import 'package:vinland/theme/mobile_theme.dart';
import 'package:vinland/theme/solid_color_effect.dart';

import '../fakes/fake_app_state.dart';
import '../fakes/fake_screen_deps.dart';

/// AppState de la page Telechargements : quelques titres telecharges.
class _DownloadsState extends FakeAppState {
  _DownloadsState(this.downloaded) : super(FakeLibrary(tracks: downloaded));

  final List<Track> downloaded;
  bool unreachable = false;
  bool offline = false;
  int bitRate = 192;
  bool removedAll = false;

  @override
  List<Track> get downloadedTracks => downloaded;
  @override
  bool get isServerUnreachable => unreachable;
  @override
  bool get offlineOnly => offline;
  @override
  bool get isOfflineMode => offline || unreachable;
  @override
  Future<void> setOfflineOnly(bool value) async {
    offline = value;
    notifyListeners();
  }

  @override
  bool get isDownloadingOffline => false;
  @override
  int get offlineQueuedCount => 0;
  @override
  int get offlineDoneCount => 0;
  @override
  Future<int> offlineBytes() async => 30 * 1024 * 1024;
  @override
  bool get autoDownloadLikes => false;
  @override
  int get offlineBitRateKbps => bitRate;
  @override
  void setOfflineBitRate(int kbps) {
    bitRate = kbps;
    notifyListeners();
  }

  @override
  Future<void> removeAllDownloads() async {
    removedAll = true;
    downloaded.clear();
    notifyListeners();
  }

  @override
  bool isTrackOffline(String trackId) => true;
  @override
  MobileThemeMode get mobileThemeMode => MobileThemeMode.solid;
  @override
  Color get mobileThemeColor => Colors.black;
  @override
  SolidColorEffect get mobileSolidEffect => SolidColorEffect.values.first;
}

Track _track(int i) => Track(
      id: 'navidrome_tr-$i',
      title: 'Titre $i',
      artist: 'Artiste',
      album: 'Album',
      duration: const Duration(minutes: 3),
    );

void main() {
  late _DownloadsState state;

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final music = MusicService(NavidromeService.withClient(SubsonicClient()));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        Provider<MusicService>.value(value: music),
      ],
      child: const MaterialApp(home: DownloadsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    state = _DownloadsState([_track(1), _track(2)]);
  });

  testWidgets('liste les titres telecharges et la place prise', (tester) async {
    await pumpPage(tester);
    expect(find.text('2 titres · 30 Mo'), findsOneWidget);
    expect(find.text('Titre 1'), findsOneWidget);
    expect(find.text('Titre 2'), findsOneWidget);
  });

  testWidgets('NAS injoignable : le bandeau le dit', (tester) async {
    state.unreachable = true;
    await pumpPage(tester);
    expect(find.textContaining('Serveur injoignable'), findsOneWidget);
  });

  testWidgets('mode hors-ligne et qualite se reglent ici', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Mode hors-ligne'));
    await tester.pumpAndSettle();
    expect(state.offline, isTrue);

    await tester.tap(find.text('320 kbps'));
    await tester.pumpAndSettle();
    expect(state.bitRate, 320);
  });

  testWidgets('tout supprimer demande confirmation', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Tout supprimer'));
    await tester.pumpAndSettle();
    expect(state.removedAll, isFalse);
    await tester.tap(find.text('Tout supprimer').last);
    await tester.pumpAndSettle();
    expect(state.removedAll, isTrue);
    expect(find.textContaining('Rien de téléchargé'), findsOneWidget);
  });
}
