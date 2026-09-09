import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import 'audio_handler.dart';
import 'just_audio_player_engine.dart';
import 'music_service.dart';
import 'navidrome_service.dart';

const _resumeChannel = MethodChannel('vinland/bluetooth_resume');
const _keyLastTrackId = 'vinland_last_track_id';
const _keyLastQueueIds = 'vinland_last_queue_ids';

/// Point d'entree d'un FlutterEngine "headless" (sans UI), demarre par
/// ResumePlaybackService.kt quand un appareil Bluetooth de confiance se
/// connecte alors que l'app n'a jamais tourne depuis le dernier redemarrage
/// du telephone. Reprend juste le dernier titre/file ecoutee, sans passer
/// par AppState ni construire le moindre widget.
@pragma('vm:entry-point')
void bluetoothResumeMain() {
  WidgetsFlutterBinding.ensureInitialized();
  _run();
}

Future<void> _run() async {
  try {
    final navidrome = NavidromeService();
    final connected = await navidrome.loadCredentials();
    if (!connected) {
      await _resumeChannel.invokeMethod('resumeFailed');
      return;
    }

    final music = MusicService();
    music.setCurrentUser(navidrome.username);
    await music.initialize();

    final prefs = await SharedPreferences.getInstance();
    final lastTrackId = prefs.getString(_keyLastTrackId);
    if (lastTrackId == null) {
      await _resumeChannel.invokeMethod('resumeFailed');
      return;
    }

    Track? findTrack(String id) {
      for (final t in music.allTracks) {
        if (t.id == id) return t;
      }
      return null;
    }

    final track = findTrack(lastTrackId);
    if (track == null) {
      await _resumeChannel.invokeMethod('resumeFailed');
      return;
    }

    final queueIds = prefs.getStringList(_keyLastQueueIds) ?? [lastTrackId];
    final queue = queueIds.map(findTrack).whereType<Track>().toList();
    final effectiveQueue = queue.isNotEmpty ? queue : [track];
    var currentIndex = effectiveQueue.indexWhere((t) => t.id == track.id);
    if (currentIndex < 0) currentIndex = 0;

    final engine = JustAudioPlayerEngine(ja.AudioPlayer(
      audioLoadConfiguration: const ja.AudioLoadConfiguration(
        androidLoadControl: ja.AndroidLoadControl(
          minBufferDuration: Duration(seconds: 30),
          maxBufferDuration: Duration(seconds: 60),
          bufferForPlaybackDuration: Duration(seconds: 5),
          bufferForPlaybackAfterRebufferDuration: Duration(seconds: 10),
        ),
      ),
    ));

    final audioHandler = await AudioService.init(
      builder: () => VinlandAudioHandler(engine),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.vinland.audio',
        androidNotificationChannelName: 'Vinland',
        androidNotificationIcon: 'drawable/ic_notification',
        androidShowNotificationBadge: true,
        androidStopForegroundOnPause: false,
      ),
    );

    final items = effectiveQueue.map((t) {
      final path = music.getOfflinePath(t.id) ?? t.filePath!;
      Uri? artUri;
      if (t.coverPath != null) {
        artUri = t.coverPath!.startsWith('http')
            ? Uri.parse(t.coverPath!)
            : Uri.file(t.coverPath!);
      }
      return MediaItem(
        id: path,
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: t.duration,
        artUri: artUri,
        extras: {
          'isAsset': path.startsWith('assets/'),
          'isRemote': path.startsWith('http'),
        },
      );
    }).toList();

    await audioHandler.loadAndPlay(items, currentIndex);
    await music.recordPlay(track.id);
    await _resumeChannel.invokeMethod('resumeStarted');
  } catch (e) {
    debugPrint('bluetoothResumeMain error: $e');
    try {
      await _resumeChannel.invokeMethod('resumeFailed');
    } catch (_) {}
  }
}
