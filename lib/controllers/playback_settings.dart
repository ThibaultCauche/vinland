import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/replay_gain.dart';

/// Reglages de lecture (Parametres > Lecture) : fondu enchaine et
/// normalisation du volume. Lus par PlayerController a chaque changement de
/// titre, sauvegardes sur l'appareil (pas de synchro entre appareils : un
/// telephone branche sur une enceinte n'a pas les memes besoins qu'un PC).
class PlaybackSettings extends ChangeNotifier {
  PlaybackSettings({
    Duration crossfade = Duration.zero,
    ReplayGainMode replayGainMode = ReplayGainMode.off,
  })  : _crossfade = crossfade,
        _replayGainMode = replayGainMode;

  static const maxCrossfade = Duration(seconds: 12);

  static const _keyCrossfadeSeconds = 'vinland_crossfade_seconds';
  static const _keyReplayGainMode = 'vinland_replaygain_mode';

  Duration _crossfade;
  ReplayGainMode _replayGainMode;

  /// 0 = pas de fondu : le titre suivant demarre a la fin du precedent
  /// (deja precharge, donc sans blanc).
  Duration get crossfade => _crossfade;
  ReplayGainMode get replayGainMode => _replayGainMode;

  Future<void> load(SharedPreferences prefs) async {
    final seconds = prefs.getInt(_keyCrossfadeSeconds) ?? 0;
    _crossfade = Duration(seconds: seconds.clamp(0, maxCrossfade.inSeconds));
    final mode = prefs.getString(_keyReplayGainMode);
    _replayGainMode = ReplayGainMode.values.firstWhere(
      (m) => m.name == mode,
      orElse: () => ReplayGainMode.off,
    );
    notifyListeners();
  }

  Future<void> setCrossfade(Duration value) async {
    final seconds = value.inSeconds.clamp(0, maxCrossfade.inSeconds);
    if (seconds == _crossfade.inSeconds) return;
    _crossfade = Duration(seconds: seconds);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCrossfadeSeconds, seconds);
  }

  Future<void> setReplayGainMode(ReplayGainMode mode) async {
    if (mode == _replayGainMode) return;
    _replayGainMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyReplayGainMode, mode.name);
  }
}
