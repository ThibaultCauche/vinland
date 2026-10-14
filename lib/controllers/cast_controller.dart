import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/cast/cast_channel.dart';
import '../services/cast/cast_discovery.dart';
import '../services/cast/cast_player_engine.dart';
import '../services/routed_player_engine.dart';

/// Ouvre la lecture sur une Chromecast, ou rejoint la session [sessionId]
/// deja ouverte ; remplace par un faux en test.
typedef CastConnector = Future<CastPlayerEngine> Function(CastDevice device,
    {String? sessionId});

Future<CastPlayerEngine> _connect(CastDevice device,
    {String? sessionId}) async {
  final channel = await CastChannel.connect(device.host, device.port);
  try {
    return sessionId == null
        ? await CastPlayerEngine.launch(channel)
        : await CastPlayerEngine.join(channel, sessionId);
  } catch (_) {
    await channel.close();
    rethrow;
  }
}

/// Diffusion sur Chromecast : recherche des appareils, connexion, retour
/// sur l'appareil. La lecture elle-meme reste pilotee comme d'habitude
/// (PlayerController) : seul le moteur actif change.
class CastController extends ChangeNotifier {
  CastController({
    required OutputSwitch output,
    CastScanner? scanner,
    CastConnector? connector,
  })  : _output = output,
        _scanner = scanner ?? BonsoirCastScanner(),
        _connector = connector ?? _connect;

  final OutputSwitch _output;
  final CastScanner _scanner;
  final CastConnector _connector;

  /// Android et Windows (bonsoir y passe par le systeme). iOS demanderait
  /// une autorisation reseau local et un build signe qu'on n'a pas.
  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  List<CastDevice> _devices = const [];
  List<CastDevice> get devices => _devices;

  bool _scanning = false;
  bool get isScanning => _scanning;

  CastDevice? _connecting;
  CastDevice? get connecting => _connecting;

  CastDevice? _device;

  /// La Chromecast sur laquelle on joue, null si on joue sur l'appareil.
  CastDevice? get device => _device;
  bool get isCasting => _device != null;

  CastPlayerEngine? _engine;
  final List<StreamSubscription<Object?>> _engineSubs = [];

  double _volume = 1.0;

  /// Volume de la Chromecast (0..1).
  double get volume => _volume;

  /// Dernier probleme a montrer (connexion ratee, diffusion coupee).
  String? _message;
  String? get message => _message;

  StreamSubscription<List<CastDevice>>? _scanSub;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Lance la recherche (a l'ouverture de la liste des appareils).
  void startScan() {
    if (_scanning) return;
    _scanning = true;
    _message = null;
    _scanSub = _scanner.scan().listen(
      (devices) {
        _devices = devices;
        _notify();
      },
      onError: (Object _) {
        _message = 'Impossible de chercher les Chromecast sur ce réseau.';
        _notify();
      },
    );
    _notify();
  }

  Future<void> stopScan() async {
    if (!_scanning) return;
    _scanning = false;
    final sub = _scanSub;
    _scanSub = null;
    // Pas de notifyListeners : appele pendant la fermeture du menu, quand
    // l'arbre de widgets est verrouille ; rien n'affiche isScanning hors
    // du menu.
    await Future.wait([if (sub != null) sub.cancel(), _scanner.stop()]);
  }

  /// Passe la lecture sur [device], au meme endroit du titre en cours.
  Future<bool> connect(CastDevice device) async {
    if (_connecting != null || device == _device) return false;
    _connecting = device;
    _message = null;
    _notify();
    CastPlayerEngine? engine;
    final previous = _engine;
    try {
      engine = await _connector(device);
      _attach(engine);
      _device = device;
      await _output.switchOutput(engine);
      if (previous != null) await _release(previous, stopReceiver: true);
      return true;
    } catch (e) {
      debugPrint('Connexion Chromecast impossible: $e');
      _message = engine == null
          ? 'Impossible de joindre ${device.name}.'
          : '${device.name} n\'arrive pas à lire ce titre. Elle doit pouvoir '
              'joindre ton serveur de musique (même réseau que le NAS).';
      if (engine != null) {
        // Lecteur lance mais titre refuse : retour sur l'appareil.
        await _backToLocal(resume: false);
        if (previous != null) await _release(previous, stopReceiver: true);
      }
      return false;
    } finally {
      _connecting = null;
      _notify();
    }
  }

  /// Reprend la lecture sur l'appareil (en pause : rien ne part a fond dans
  /// la poche) et arrete le lecteur sur la tele.
  Future<void> disconnect() async {
    if (_engine == null) return;
    _message = null;
    await _backToLocal(resume: false);
  }

  void _attach(CastPlayerEngine engine) {
    for (final sub in _engineSubs) {
      unawaited(sub.cancel());
    }
    _engineSubs.clear();
    _engine = engine;
    _volume = engine.deviceVolume;
    _engineSubs
      ..add(engine.ended.listen((_) => unawaited(_onEnded(engine))))
      ..add(engine.deviceVolumeStream.listen((v) {
        _volume = v;
        _notify();
      }));
  }

  Future<void> _onEnded(CastPlayerEngine engine) async {
    if (!identical(engine, _engine)) return;
    // Liaison coupee mais la tele continue de jouer : on reprend la main
    // dessus. Revenir sur l'appareil la laisserait jouer sans telecommande
    // (et Play relancerait le titre en double sur le telephone).
    final device = _device;
    final sessionId = engine.sessionId;
    if (engine.lostLink && device != null && sessionId != null) {
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          final rejoined = await _connector(device, sessionId: sessionId);
          if (!identical(engine, _engine)) {
            // Deconnecte entre-temps par l'utilisateur.
            await _release(rejoined, stopReceiver: false);
            return;
          }
          _attach(rejoined);
          _output.adoptOutput(rejoined);
          await _release(engine, stopReceiver: false);
          _notify();
          return;
        } on StateError {
          // Notre lecteur est ferme sur la tele : rien a reprendre.
          break;
        } catch (e) {
          debugPrint('Reprise Chromecast impossible ($attempt/3): $e');
          if (!identical(engine, _engine)) return;
          await Future<void>.delayed(Duration(seconds: attempt));
        }
      }
    }
    _message = 'La diffusion sur ${_device?.name ?? 'la Chromecast'} '
        's\'est arrêtée.';
    await _backToLocal(resume: false);
  }

  Future<void> _backToLocal({required bool resume}) async {
    final engine = _engine;
    _engine = null;
    _device = null;
    for (final sub in _engineSubs) {
      unawaited(sub.cancel());
    }
    _engineSubs.clear();
    try {
      await _output.switchOutput(_output.localEngine, resume: resume);
    } catch (e) {
      debugPrint('Reprise locale impossible: $e');
    }
    if (engine != null) await _release(engine, stopReceiver: true);
    _notify();
  }

  Future<void> _release(
    CastPlayerEngine engine, {
    required bool stopReceiver,
  }) async {
    try {
      await engine.disconnect(stopReceiver: stopReceiver && !engine.isEnded);
    } catch (_) {
      // Connexion deja perdue.
    }
  }

  Future<void> setVolume(double volume) async {
    final engine = _engine;
    if (engine == null) return;
    _volume = volume;
    _notify();
    await engine.setVolume(volume);
  }

  void clearMessage() {
    if (_message == null) return;
    _message = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_scanSub?.cancel());
    unawaited(_scanner.stop());
    final engine = _engine;
    if (engine != null) unawaited(_release(engine, stopReceiver: true));
    super.dispose();
  }
}
