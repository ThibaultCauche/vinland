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
      child: ChangeNotifierProvider(
        create: (_) => AppState(audioHandler: audioHandler)..initialize(),
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
    return Consumer<AppState>(
      builder: (context, state, child) {
        if (!state.isLoggedIn) return const LoginScreen();

        final screens = [
          const HomeScreen(),
          const LibraryScreen(),
          const FriendsScreen(),
        ];

        return PopScope(
          canPop: state.overlayStack.isEmpty && state.currentTab == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              if (state.overlayStack.isNotEmpty) {
                state.popOverlay();
              } else if (state.currentTab != 0) {
                state.setTab(0);
              }
            }
          },
          child: Scaffold(
            extendBody: true,
            extendBodyBehindAppBar: true,
            body: Stack(
              children: [
                screens[state.currentTab],
                if (state.currentOverlay != null)
                  Positioned.fill(child: state.currentOverlay!),
              ],
            ),
            bottomNavigationBar: SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.currentTrack != null &&
                      state.currentOverlay is! PlayerScreen)
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
