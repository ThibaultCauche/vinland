import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../providers/app_state.dart';

/// Ce que les boutons de la barre des taches pilotent : AppState dans
/// l'app, un faux dans les tests.
abstract class TaskbarPlayback implements Listenable {
  bool get hasTrack;
  bool get isPlaying;
  void togglePlayPause();
  Future<void> nextTrack();
  Future<void> previousTrack();
}

/// Boutons precedent / lecture-pause / suivant dans l'apercu de la fenetre,
/// au survol de l'icone Vinland dans la barre des taches Windows (comme
/// Spotify). Le dessin et les clics sont natifs
/// (windows/runner/taskbar_controls.cpp) ; ici on tient l'icone
/// lecture/pause a jour et on relaie les clics.
class TaskbarControls {
  TaskbarControls(
    this._playback, {
    MethodChannel channel = const MethodChannel('vinland/taskbar'),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_onCall);
    _playback.addListener(_sync);
    _sync();
  }

  final TaskbarPlayback _playback;
  final MethodChannel _channel;
  bool? _enabled;
  bool? _playing;

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'onButton') return;
    switch (call.arguments) {
      case 'previous':
        await _playback.previousTrack();
      case 'playPause':
        _playback.togglePlayPause();
      case 'next':
        await _playback.nextTrack();
    }
  }

  /// AppState notifie souvent : on ne parle au natif que quand l'etat des
  /// boutons change vraiment.
  void _sync() {
    final enabled = _playback.hasTrack;
    final playing = enabled && _playback.isPlaying;
    if (enabled != _enabled) {
      _enabled = enabled;
      _send('setEnabled', enabled);
    }
    if (playing != _playing) {
      _playing = playing;
      _send('setPlaying', playing);
    }
  }

  void _send(String method, bool value) {
    _channel.invokeMethod<void>(method, value).catchError((Object e) {
      debugPrint('Barre des taches $method: $e');
    });
  }

  void dispose() {
    _playback.removeListener(_sync);
    _channel.setMethodCallHandler(null);
  }
}

/// [TaskbarPlayback] branche sur l'app : ce que montre la barre de lecture
/// (y compris l'hote suivi en synchro perso).
class AppStateTaskbarPlayback implements TaskbarPlayback {
  AppStateTaskbarPlayback(this._state);

  final AppState _state;

  @override
  bool get hasTrack => _state.displayTrack != null;
  @override
  bool get isPlaying => _state.displayIsPlaying;
  @override
  void togglePlayPause() => _state.togglePlayPause();
  @override
  Future<void> nextTrack() => _state.nextTrack();
  @override
  Future<void> previousTrack() => _state.previousTrack();
  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);
}
