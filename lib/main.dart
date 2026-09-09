import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/friends_screen.dart';
import 'services/audio_handler.dart';
import 'services/player_engine.dart';
import 'services/just_audio_player_engine.dart';
import 'services/media_kit_player_engine.dart';
import 'widgets/mini_player.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/player_screen.dart';
import 'services/music_service.dart';
import 'models/track.dart';
import 'desktop/desktop_app_shell.dart';

/// Vinland tourne en shell "verre" desktop sur Windows/macOS/Linux (visuel
/// inspire de https://www.behance.net/gallery/174341245/Spotify-Visual-Ui),
/// et garde le shell mobile classique (bottom nav) partout ailleurs. Sur le
/// web on bascule aussi en desktop des que la fenetre est large : ca sert
/// de previsualisation rapide dans un navigateur (Edge/Chrome) sans avoir
/// besoin du toolchain Visual Studio requis pour le build Windows natif.
bool _isDesktopLayout(double width) =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux ||
    (kIsWeb && width >= 900);

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Empeche une erreur de rendu Flutter (ex: stream reseau en erreur)
    // de faire planter completement l'application.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FLUTTER ERROR: ${details.exceptionAsString()}');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('UNCAUGHT ERROR: $error\n$stack');
      return true;
    };

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ));

    if (defaultTargetPlatform == TargetPlatform.android) {
      // Necessaire sur Android 13+ pour que la notification de lecture
      // (et donc le foreground service audio) puisse s'afficher correctement.
      await Permission.notification.request();
    }

    // just_audio ne declare aucune implementation Windows/Linux : sur ces
    // plateformes on passe par media_kit (libmpv) a la place. Ailleurs
    // (Android/iOS/macOS/web), just_audio + audio_service reste le combo
    // le plus mature pour la notification/lock screen.
    final bool useMediaKit = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;

    final PlayerEngine engine;
    if (useMediaKit) {
      MediaKit.ensureInitialized();
      engine = MediaKitPlayerEngine();
    } else {
      engine = JustAudioPlayerEngine(ja.AudioPlayer(
        // Buffers plus genereux : absorbe les micro-coupures dues a la
        // latence variable du lien Tailscale vers le NAS au lieu de couper
        // le son.
        audioLoadConfiguration: const ja.AudioLoadConfiguration(
          androidLoadControl: ja.AndroidLoadControl(
            minBufferDuration: Duration(seconds: 30),
            maxBufferDuration: Duration(seconds: 60),
            bufferForPlaybackDuration: Duration(seconds: 5),
            bufferForPlaybackAfterRebufferDuration: Duration(seconds: 10),
          ),
        ),
      ));
    }

    final audioHandler = await AudioService.init(
      builder: () => VinlandAudioHandler(engine),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.vinland.audio',
        androidNotificationChannelName: 'Vinland',
        androidNotificationIcon: 'drawable/ic_notification',
        androidShowNotificationBadge: true,
        // Par defaut (true), le foreground service se retire des qu'il y a
        // une pause meme transitoire (perte de focus audio quand TikTok/une
        // autre app lance une video avec du son, micro-coupure reseau...).
        // Une fois retire, le processus entier de l'app perd sa protection
        // contre le "low memory killer" d'Android et se fait tuer en
        // arriere-plan des qu'une autre app (TikTok...) consomme de la
        // memoire -- ce qui ressemble a l'app qui "se kill toute seule".
        // NB: androidNotificationOngoing doit rester false ici (valeur par
        // defaut) : audio_service impose ongoing=true des que
        // stopForegroundOnPause=false, ce sera donc deja le comportement
        // reel, et le combo inverse (ongoing=true + stopForegroundOnPause
        // =false) est explicitement rejete par une assertion du package.
        androidStopForegroundOnPause: false,
      ),
    );

    runApp(VinlandApp(audioHandler: audioHandler));
  }, (error, stack) {
    debugPrint('ZONE ERROR: $error\n$stack');
  });
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
          // Le shell desktop a des barres a hauteur fixe (sidebar, barre de
          // lecture) : un scaling de texte systeme trop agressif (ex: reglage
          // d'accessibilite Windows "Taille du texte") les fait deborder
          // catastrophiquement. On respecte l'accessibilite jusqu'a 1.3x,
          // au-dela on plafonne plutot que de casser la mise en page.
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: 1.0,
            maxScaleFactor: 1.3,
            child: child!,
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
    return Selector<AppState, (bool, bool, int, Widget?, Track?)>(
      selector: (_, state) => (
        state.isInitializing,
        state.isLoggedIn,
        state.currentTab,
        state.currentOverlay,
        state.currentTrack,
      ),
      builder: (context, data, child) {
        final (isInitializing, isLoggedIn, currentTab, currentOverlay, currentTrack) =
            data;

        // Chargement du cache local + tentative de connexion Navidrome au
        // demarrage : evite un flash de l'ecran de connexion pendant que le
        // ping reseau vers le NAS repond (peut prendre plusieurs secondes).
        if (isInitializing) return const _SplashScreen();

        // ── AUTH ──
        if (!isLoggedIn) return const LoginScreen();

        // Récupère state ICI, avant de l'utiliser
        final state = context.read<AppState>();

        return LayoutBuilder(
          builder: (context, constraints) {
            if (_isDesktopLayout(constraints.maxWidth)) {
              return const DesktopAppShell();
            }
            return _MobileAppShell(
              currentTab: currentTab,
              currentOverlay: currentOverlay,
              state: state,
            );
          },
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF121212),
      body: Center(
        child: Icon(Icons.music_note, color: Color(0xFF1DB954), size: 64),
      ),
    );
  }
}

class _MobileAppShell extends StatelessWidget {
  final int currentTab;
  final Widget? currentOverlay;
  final AppState state;

  const _MobileAppShell({
    required this.currentTab,
    required this.currentOverlay,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
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
            if (currentOverlay != null) Positioned.fill(child: currentOverlay!),
          ],
        ),
        bottomNavigationBar: currentOverlay is PlayerScreen
            ? null
            : SafeArea(
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
  }
}
