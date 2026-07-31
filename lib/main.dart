import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:metadata_god/metadata_god.dart';
import 'services/audio_handler.dart';
import 'providers/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/friends_screen.dart';
import 'widgets/mini_player.dart';
import 'widgets/bottom_nav.dart';
import 'package:just_audio/just_audio.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MetadataGod.initialize();

  final player = AudioPlayer();
  final audioHandler = await AudioService.init(
    builder: () => VinlandAudioHandler(player),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.vinland.audio',
      androidNotificationChannelName: 'Vinland',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(VinlandApp(audioHandler: audioHandler));
}

class VinlandApp extends StatelessWidget {
  final VinlandAudioHandler audioHandler;
  const VinlandApp({super.key, required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(audioHandler: audioHandler)..initialize(),
      child: MaterialApp(
        title: 'Vinland',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF121212),
        ),
        home: const AppShell(),
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
        if (!state.isLoggedIn) {
          return const LoginScreen();
        }

        final screens = [
          const HomeScreen(),
          const LibraryScreen(),
          const FriendsScreen(),
        ];

        final bottomPadding = MediaQuery.of(context).padding.bottom;
        final navHeight = kBottomNavigationBarHeight + bottomPadding;

        // Détermine si le mini-player doit être visible
        // On le cache si on est sur le PlayerScreen (overlay)
        final bool showMiniPlayer =
            state.currentTrack != null && state.currentOverlay == null;

        final canPop = state.overlayStack.isEmpty && state.currentTab == 0;

        return PopScope(
          canPop: canPop,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;

            if (state.overlayStack.isNotEmpty) {
              state.popOverlay();
            } else if (state.currentTab != 0) {
              state.setTab(0);
            }
          },
          child: Scaffold(
            body: Stack(
              children: [
                state.currentOverlay ?? screens[state.currentTab],
                if (showMiniPlayer)
                  Positioned(
                    bottom: navHeight + 8,
                    left: 8,
                    right: 8,
                    child: const MiniPlayer(),
                  ),
              ],
            ),
            bottomNavigationBar: const BottomNav(),
          ),
        );
      },
    );
  }
}
