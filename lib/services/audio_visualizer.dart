import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Niveaux instantanes de la musique, 0..1.
class AudioLevels {
  const AudioLevels(this.bass, this.mid);
  final double bass;
  final double mid;
}

/// Niveaux de la musique en cours pour le visuel du lecteur (grille
/// d'hexagones, voir HexPulseVisualizer).
///
/// Android seulement : l'analyse est faite par AudioVisualizer.kt, branche
/// sur les sessions audio des platines just_audio. Ailleurs (Windows,
/// lecture sur Chromecast, participant d'une Jam) il n'y a rien a analyser
/// localement et le visuel pulse tout seul, doucement.
///
/// L'analyse ne tourne que tant qu'un visuel est affiche ([attach] /
/// [detach]) et que l'app est au premier plan : rien ne tourne en fond.
class AudioVisualizer with WidgetsBindingObserver {
  AudioVisualizer({
    List<Stream<int?>> sessionIds = const [],
    MethodChannel channel = const MethodChannel('vinland/visualizer'),
    EventChannel events = const EventChannel('vinland/visualizer/levels'),
  })  : _channel = channel,
        _events = events {
    for (var i = 0; i < sessionIds.length; i++) {
      _sessions.add(null);
      final deck = i;
      sessionIds[i].listen((id) {
        _sessions[deck] = id;
        if (_running) unawaited(_start());
      });
    }
    if (supported) WidgetsBinding.instance.addObserver(this);
  }

  /// Aucun moteur analysable (Windows, tests) : visuel au repos seulement.
  AudioVisualizer.disabled() : this();

  static const _keyPermissionAsked = 'vinland_visualizer_permission_asked';

  final MethodChannel _channel;
  final EventChannel _events;
  final List<int?> _sessions = [];
  StreamSubscription<dynamic>? _sub;
  int _attached = 0;
  bool _running = false;
  bool _foreground = true;

  AudioLevels? _latest;
  final Stopwatch _sinceSample = Stopwatch();

  bool get supported => _sessions.isNotEmpty;

  /// Derniere mesure, ou null si rien n'est arrive depuis un moment (pause,
  /// permission refusee, lecture sur Chromecast) : le visuel passe alors au
  /// repos.
  AudioLevels? get latest {
    if (_latest == null || _sinceSample.elapsedMilliseconds > 400) return null;
    return _latest;
  }

  void attach() {
    _attached++;
    _update();
  }

  void detach() {
    _attached = (_attached - 1).clamp(0, 1 << 30);
    _update();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _update();
  }

  void _update() {
    final shouldRun = supported && _attached > 0 && _foreground;
    if (shouldRun == _running) return;
    _running = shouldRun;
    if (shouldRun) {
      _sub = _events.receiveBroadcastStream().listen(_onSample,
          onError: (Object e) => debugPrint('Visualiseur: $e'));
      unawaited(_start());
    } else {
      unawaited(_sub?.cancel());
      _sub = null;
      _latest = null;
      unawaited(_invoke('stop'));
    }
  }

  Future<void> _start() async {
    if (!await Permission.microphone.isGranted) return;
    final ids = _sessions.whereType<int>().where((id) => id > 0).toList();
    if (ids.isEmpty) return;
    await _invoke('start', {'sessionIds': ids});
  }

  Future<void> _invoke(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<Object?>(method, args);
    } on PlatformException catch (e) {
      debugPrint('Visualiseur $method: $e');
    } on MissingPluginException {
      // Pas de code natif (tests, autre plateforme).
    }
  }

  void _onSample(dynamic data) {
    if (data is! List || data.length < 2) return;
    _latest = AudioLevels(
      (data[0] as num).toDouble(),
      (data[1] as num).toDouble(),
    );
    _sinceSample
      ..reset()
      ..start();
  }

  /// Demande une seule fois l'acces au son (Android l'appelle « micro ») :
  /// [explain] montre d'abord pourquoi, et renvoie false si l'utilisateur
  /// prefere s'en passer. Le visuel marche sans, au repos.
  Future<void> askPermissionOnce(Future<bool> Function() explain) async {
    if (!supported) return;
    if (await Permission.microphone.isGranted) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyPermissionAsked) ?? false) return;
    await prefs.setBool(_keyPermissionAsked, true);
    if (!await explain()) return;
    if (await Permission.microphone.request().isGranted && _running) {
      await _start();
    }
  }

  /// Depuis les parametres : redemande meme si on a deja demande.
  Future<bool> requestPermission() async {
    if (!supported) return false;
    final status = await Permission.microphone.request();
    if (status.isPermanentlyDenied) await openAppSettings();
    if (status.isGranted && _running) await _start();
    return status.isGranted;
  }

  Future<bool> get hasPermission async =>
      supported && await Permission.microphone.isGranted;
}
