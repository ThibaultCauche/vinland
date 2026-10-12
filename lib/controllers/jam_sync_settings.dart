import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Decalage audio de CET appareil pendant un Jam (menu Jam > Decalage
/// audio). Un casque ou une enceinte Bluetooth joue le son 100 a 300 ms
/// apres que le lecteur l'a lu : la position du lecteur est alignee, pas ce
/// qu'on entend. Le reglage dit de combien cet appareil doit jouer en
/// avance pour compenser. Sauvegarde sur l'appareil seulement : la latence
/// depend de la sortie audio branchee, pas du compte.
class JamSyncSettings extends ChangeNotifier {
  JamSyncSettings({Duration offset = Duration.zero}) : _offset = offset;

  static const maxOffset = Duration(milliseconds: 500);
  static const step = Duration(milliseconds: 10);

  static const _keyOffsetMs = 'vinland_jam_offset_ms';

  Duration _offset;

  /// Positif : cet appareil joue en avance (sortie Bluetooth lente).
  Duration get offset => _offset;

  Future<void> load(SharedPreferences prefs) async {
    _offset = _clamp(prefs.getInt(_keyOffsetMs) ?? 0);
    notifyListeners();
  }

  Future<void> setOffset(Duration value) async {
    final clamped = _clamp(value.inMilliseconds);
    if (clamped == _offset) return;
    _offset = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyOffsetMs, clamped.inMilliseconds);
  }

  static Duration _clamp(int ms) {
    final max = maxOffset.inMilliseconds;
    final stepMs = step.inMilliseconds;
    final rounded = (ms / stepMs).round() * stepMs;
    return Duration(milliseconds: rounded.clamp(-max, max));
  }
}
