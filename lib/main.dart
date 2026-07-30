import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:metadata_god/metadata_god.dart';
import 'providers/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/friends_screen.dart';
import 'widgets/mini_player.dart';
import 'widgets/bottom_nav.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MetadataGod.initialize();
  runApp(const VinlandApp());
}

class VinlandApp extends StatelessWidget {
  const VinlandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..initialize(),
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

        return Scaffold(
          body: Stack(
            children: [
              state.currentOverlay ?? screens[state.currentTab],
              if (state.currentTrack != null)
                const Positioned(
                  bottom: 20,
                  left: 8,
                  right: 8,
                  child: MiniPlayer(),
                ),
            ],
          ),
          bottomNavigationBar: const BottomNav(),
        );
      },
    );
  }
}
