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
/// de vagues, voir PulseWavesVisualizer).
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

  /// Mesures recues, datees sur [_clock], en attente d'etre affichees.
  final List<(Duration, AudioLevels)> _pending = [];
  final Stopwatch _clock = Stopwatch()..start();

  /// L'analyse entend le son avant le haut-parleur (voir outputLatencyMs
  /// dans AudioVisualizer.kt) : on affiche chaque mesure avec ce retard
  /// pour que les vagues tombent en meme temps que les basses.
  Duration _delay = const Duration(milliseconds: 350);

  bool get supported => _sessions.isNotEmpty;

  /// Derniere mesure, ou null si rien n'est arrive depuis un moment (pause,
  /// permission refusee, lecture sur Chromecast) : le visuel passe alors au
  /// repos.
  AudioLevels? get latest {
    final due = _clock.elapsed - _delay;
    while (_pending.length > 1 && _pending[1].$1 <= due) {
      _pending.removeAt(0);
    }
    if (_pending.isEmpty) return null;
    final (at, levels) = _pending.first;
    if (at > due || due - at > const Duration(milliseconds: 400)) return null;
    return levels;
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
      _pending.clear();
      unawaited(_invoke('stop'));
    }
  }

  Future<void> _start() async {
    if (!await Permission.microphone.isGranted) return;
    final ids = _sessions.whereType<int>().where((id) => id > 0).toList();
    if (ids.isEmpty) return;
    await _invoke('start', {'sessionIds': ids});
    final latency = await _invoke('latency');
    if (latency is int && latency >= 0) {
      _delay = Duration(milliseconds: latency);
    }
  }

  Future<Object?> _invoke(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } on PlatformException catch (e) {
      debugPrint('Visualiseur $method: $e');
    } on MissingPluginException {
      // Pas de code natif (tests, autre plateforme).
    }
    return null;
  }

  void _onSample(dynamic data) {
    if (data is! List || data.length < 2) return;
    _pending.add((
      _clock.elapsed,
      AudioLevels((data[0] as num).toDouble(), (data[1] as num).toDouble()),
    ));
    // Garde-fou si personne ne lit (visuel cache) : ~2 s de mesures.
    if (_pending.length > 40) _pending.removeAt(0);
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
