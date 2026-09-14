import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:just_audio/just_audio.dart' as ja;
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:metadata_god/metadata_god.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'providers/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/friends_screen.dart';
import 'services/audio_handler.dart';
import 'services/player_engine.dart';
import 'services/just_audio_player_engine.dart';
import 'services/media_kit_player_engine.dart';
import 'services/deep_link_service.dart';
import 'widgets/mini_player.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/player_screen.dart';
import 'widgets/update_prompt.dart';
import 'services/music_service.dart';
import 'models/track.dart';
import 'desktop/desktop_app_shell.dart';
import 'desktop/desktop_theme.dart';
import 'widgets/app_background.dart';

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

    // Requis avant tout appel a MetadataGod.readMetadata (lecture des tags
    // ID3/Vorbis d'un fichier local) : sans cet appel, chaque lecture leve
    // "Bad state: MetadataGod not initialized" -- capture silencieuse par
    // les try/catch appelants (MusicService.parseFile, AppState._readLocalTags
    // pour la detection de doublon a l'import), donc le symptome n'etait
    // qu'un repli permanent sur le nom de fichier, jamais une erreur visible.
    MetadataGod.initialize();

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
      // Vinland est installe en sideload (zip/APK telecharge, pas le Play
      // Store) : contrairement a Spotify, qui beneficie sur beaucoup d'OEM
      // (Samsung, Xiaomi...) d'une liste blanche automatique des apps Play
      // Store connues/frequentes, Vinland n'a par defaut aucun traitement
      // de faveur des gestionnaires de batterie constructeur et se fait
      // tuer en fond bien plus facilement (retour utilisateur : coupures
      // pendant un trajet, changement d'appli en salle de sport). On
      // demande donc explicitement l'exemption ici (popup systeme standard)
      // au lieu de compter sur l'utilisateur pour la trouver lui-meme dans
      // les reglages -- no-op silencieux si deja accordee/refusee.
      await Permission.ignoreBatteryOptimizations.request();
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      // Fenetre sans bordure/barre de titre native (la barre custom avec ses
      // propres boutons vit dans DesktopTitleBar) + fond de fenetre
      // transparent : DesktopBackground n'a alors plus qu'a laisser passer
      // les zones sans contenu pour voir litteralement le bureau/ce qu'il y
      // a derriere, au lieu de simuler ca avec une cover floutee.
      await windowManager.ensureInitialized();
      await acrylic.Window.initialize();
      const windowOptions = WindowOptions(
        size: Size(1280, 800),
        minimumSize: Size(1000, 650),
        center: true,
        backgroundColor: Colors.transparent,
        titleBarStyle: TitleBarStyle.hidden,
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      // Applique l'effet de fenetre correspondant au theme choisi par
      // l'utilisateur (Parametres > Apparence) -- transparent uniquement
      // pour le theme "transparent", desactive sinon. Voir desktop_theme.dart.
      await DesktopTheme.applyWindowEffect(await DesktopTheme.loadMode());
    }

    // just_audio ne declare aucune implementation Windows/Linux : sur ces
    // plateformes on passe par media_kit (libmpv) a la place. Ailleurs
    // (Android/iOS/macOS/web), just_audio + audio_service reste le combo
    // le plus mature pour la notification/lock screen.
    final bool useMediaKit = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);

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

    final appState = AppState(audioHandler: audioHandler);
    appState.initialize();
    DeepLinkService(appState).init();

    runApp(VinlandApp(audioHandler: audioHandler, appState: appState));
  }, (error, stack) {
    debugPrint('ZONE ERROR: $error\n$stack');
  });
}

class VinlandApp extends StatelessWidget {
  final VinlandAudioHandler audioHandler;
  final AppState appState;
  const VinlandApp(
      {super.key, required this.audioHandler, required this.appState});

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
          ChangeNotifierProvider<AppState>.value(value: appState),
          Provider<MusicService>.value(value: MusicService()),
          Provider<VinlandAudioHandler>.value(value: audioHandler),
        ],
        child: MaterialApp(
          navigatorKey: vinlandNavigatorKey,
          title: 'Vinland',
          debugShowCheckedModeBanner: false,
          scrollBehavior: _VinlandScrollBehavior(),
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
        final (
          isInitializing,
          isLoggedIn,
          currentTab,
          currentOverlay,
          currentTrack
        ) = data;

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
        child: Image(
          image: AssetImage('assets/icon/app_icon_foreground.png'),
          width: 96,
          height: 96,
        ),
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

    // Sur Android, la mise a jour est proposee directement a l'ouverture
    // (au lieu du bandeau retire de l'accueil) -- une seule fois par
    // session, voir AppState.updatePromptShown.
    if (defaultTargetPlatform == TargetPlatform.android &&
        state.updateInfo != null &&
        !state.updatePromptShown) {
      state.updatePromptShown = true;
      final update = state.updateInfo!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) showUpdateDialog(context, update);
      });
    }

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
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: AppBackground(
          child: Stack(
            children: [
              // Demonte comple entierement l'ecran de l'onglet pendant
              // qu'un overlay (recherche/artiste/album...) est affiche,
              // plutot que de le garder cache en arriere-plan (essaye
              // d'abord avec Offstage : le moteur de rendu Impeller
              // recomposait alors le fond commun par-dessus tout le reste,
              // ecran entierement voile -- retour testeur). Cout accepte :
              // l'onglet perd sa position de scroll pendant que l'overlay
              // est ouvert, ce qui reste un compromis mineur a cote d'un
              // ecran illisible. Avant ce demontage, l'ecran de l'onglet
              // restant monte laissait aussi transparaitre son contenu
              // derriere les Scaffold transparents des overlays (autre
              // retour testeur).
              if (currentOverlay == null) screens[currentTab],
              if (currentOverlay != null)
                Positioned.fill(child: currentOverlay!),
            ],
          ),
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

/// Comportement de scroll partage par toute l'app : physique "bouncing"
/// partout (rebond doux en fin de liste au lieu d'un arret sec) pour une
/// sensation plus fluide en parcourant l'app. Le lissage de la molette de
/// souris (le vrai objet de la demande) est gere separement, vue par vue,
/// par SmoothMouseScroll (voir lib/widgets/smooth_scroll.dart) : Flutter ne
/// l'anime jamais par defaut, molette ou pas, donc ca ne peut pas se
/// configurer globalement ici.
class _VinlandScrollBehavior extends MaterialScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }
}
