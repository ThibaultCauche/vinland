import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // ← Rend la barre de navigation Android transparente
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      statusBarColor: Colors.transparent,
    ),
  );

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

        // ← On récupère juste le padding système (gesture nav bar)
        final bottomSafePadding = MediaQuery.of(context).padding.bottom;

        // Hauteur de la bottom nav Flutter (56px) + padding système
        final totalNavHeight = kBottomNavigationBarHeight + bottomSafePadding;

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
            // ← Pas de resizeToAvoidBottomInset, on gère nous-mêmes
            resizeToAvoidBottomInset: false,
            body: Stack(
              children: [
                // ← Le contenu principal prend TOUT l'écran, y compris sous la nav
                Positioned.fill(
                  child: state.currentOverlay ?? screens[state.currentTab],
                ),
                // ← Mini-player collé AU-DESSUS de la bottom nav
                if (showMiniPlayer)
                  Positioned(
                    bottom: totalNavHeight,
                    left: 0,
                    right: 0,
                    child: const MiniPlayer(),
                  ),
              ],
            ),
            // ← Bottom nav sans container extérieur, on gère le padding dans le widget
            bottomNavigationBar: const BottomNav(),
          ),
        );
      },
    );
  }
}
