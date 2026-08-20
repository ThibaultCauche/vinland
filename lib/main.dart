import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/friends_screen.dart';
import 'services/audio_handler.dart';
import 'widgets/mini_player.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/player_screen.dart';
import 'services/music_service.dart';
import 'models/track.dart';
import 'models/vinland_user.dart';
import './screens/pending_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  ));

  final player = AudioPlayer();
  final audioHandler = await AudioService.init(
    builder: () => VinlandAudioHandler(player),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.vinland.audio',
      androidNotificationChannelName: 'Vinland',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'drawable/ic_notification',
      androidShowNotificationBadge: true,
    ),
  );

  runApp(VinlandApp(audioHandler: audioHandler));
}

class VinlandApp extends StatelessWidget {
  final VinlandAudioHandler audioHandler;
  const VinlandApp({super.key, required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AppState(audioHandler: audioHandler)..initialize(),
          ),
          Provider<MusicService>.value(value: MusicService()),
          Provider<VinlandAudioHandler>.value(value: audioHandler),
        ],
        child: MaterialApp(
          title: 'Vinland',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF121212),
          ),
          home: const AppShell(),
        ),
      ),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (bool, int, Widget?, Track?)>(
      selector: (_, state) => (
        state.isLoggedIn,
        state.currentTab,
        state.currentOverlay,
        state.currentTrack,
      ),
      builder: (context, data, child) {
        final (isLoggedIn, currentTab, currentOverlay, currentTrack) = data;

        // ── AUTH ──
        if (!isLoggedIn) return const LoginScreen();

        // Récupère state ICI, avant de l'utiliser
        final state = context.read<AppState>();

        if (state.currentUser?.status == UserStatus.pending) {
          return const PendingScreen();
        }

        final screens = [
          const HomeScreen(),
          const LibraryScreen(),
          const FriendsScreen(),
        ];

        return PopScope(
          canPop: currentOverlay == null && currentTab == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              if (currentOverlay != null) {
                state.popOverlay();
              } else if (currentTab != 0) {
                state.setTab(0);
              }
            }
          },
          child: Scaffold(
            extendBody: true,
            extendBodyBehindAppBar: true,
            body: Stack(
              children: [
                screens[currentTab],
                if (currentOverlay != null)
                  Positioned.fill(child: currentOverlay!),
              ],
            ),
            bottomNavigationBar: SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: MiniPlayer(),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.0),
                          Colors.black.withOpacity(0.85),
                          Colors.black.withOpacity(1.0),
                        ],
                        stops: const [0.0, 0.3, 1.0],
                      ),
                    ),
                    child: const BottomNav(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
