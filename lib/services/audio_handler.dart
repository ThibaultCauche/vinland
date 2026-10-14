import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'deck_player_engine.dart';
import 'media_browser.dart';
import 'player_engine.dart';
import 'routed_player_engine.dart';

class VinlandAudioHandler extends BaseAudioHandler
    with SeekHandler
    implements PlaybackOutput, OutputSwitch {
  final PlayerEngine _engine;
  @override
  PlayerEngine get player => _engine;

  /// Les platines locales, si elles jouent en ce moment (pas pendant une
  /// diffusion Chromecast, ni avec le moteur simple de la reprise
  /// Bluetooth) : prechargement et fondu n'existent que la.
  DeckPlayerEngine? get _deck {
    final engine = _engine;
    if (engine is DeckPlayerEngine) return engine;
    if (engine is RoutedPlayerEngine) {
      final active = engine.active;
      if (active is DeckPlayerEngine) return active;
    }
    return null;
  }

  /// Bibliotheque vue par Android Auto (voir VinlandMediaBrowser), branchee
  /// par AppState. Null : rien a parcourir (entree Bluetooth en
  /// arriere-plan, ou bibliotheque pas encore chargee).
  VinlandMediaBrowser? browser;

  final _customActionController = StreamController<String>.broadcast();
  Stream<String> get customActionStream => _customActionController.stream;

  VinlandAudioHandler(this._engine) {
    // Le PlaybackState remonte a audio_service (notification/lock screen
    // Android) est recalcule a chaque changement pertinent -- generique,
    // ne depend plus du backend (just_audio ou media_kit).
    _engine.positionStream.listen(
      (_) => _pushState(),
      onError: (Object e, StackTrace st) {
        // Une erreur reseau/decodage ponctuelle ne doit pas remonter
        // non-geree et faire planter l'app : on la journalise seulement.
        debugPrint('PLAYBACK EVENT ERROR: $e');
      },
    );
    _engine.playingStream.listen((_) => _pushState());
    _engine.currentIndexStream.listen((index) {
      _updateMediaItemFromIndex(index);
      _pushState();
    });

    _engine.errorMessages.listen((msg) {
      debugPrint('AUDIO ERROR: $msg');
    });

    _engine.durationStream.listen((duration) {
      final index = _engine.currentIndex;
      if (duration != null &&
          index != null &&
          index >= 0 &&
          index < queue.value.length) {
        final item = queue.value[index];
        mediaItem.add(MediaItem(
          id: item.id,
          title: item.title,
          artist: item.artist,
          album: item.album,
          duration: duration,
          artUri: item.artUri,
          extras: item.extras,
        ));
      }
    });
  }

  void _pushState() {
    try {
      playbackState.add(_transformState());
    } catch (e) {
      debugPrint('PLAYBACK STATE PUSH ERROR: $e');
    }
  }

  void _updateMediaItemFromIndex(int? index) {
    if (index == null || index < 0 || index >= queue.value.length) return;
    final item = queue.value[index];
    mediaItem.add(item);
  }

  @override
  Future<void> play() => _engine.play();
  @override
  Future<void> pause() => _engine.pause();
  @override
  Future<void> seek(Duration position) => _engine.seek(position);

  // Ne pilotent PAS _engine.seekToNext()/seekToPrevious() (ancien
  // comportement) : le moteur ne reçoit jamais qu'UN SEUL titre a la fois
  // (voir PlayerController._playSingle), la file d'attente entiere vit cote Dart
  // dans PlayQueue -- seekToNext/Previous du moteur natif n'avaient
  // donc litteralement rien a faire dans une file d'un seul element. Ca
  // rendait les boutons suivant/precedent inertes depuis la notification/
  // l'ecran verrouille et les gestes du casque Bluetooth (seul play/pause
  // marchait, lui pilote reellement le meme moteur quelle que soit la
  // source -- retour utilisateur). Relaie plutot via customActionStream,
  // deja ecoute par AppState (meme canal que 'add_to_likes'), qui appelle
  // sa vraie logique nextTrack()/previousTrack() (avance la file Dart,
  // historique, alea, synchro perso...).
  @override
  Future<void> skipToNext() async {
    _customActionController.add('skip_next');
  }

  @override
  Future<void> skipToPrevious() async {
    _customActionController.add('skip_previous');
  }

  @override
  Future<void> stop() async {
    await _engine.stop();
    await super.stop();
  }

  // --- Android Auto : parcourir et lancer depuis la voiture ---------------

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
          [Map<String, dynamic>? options]) async =>
      await browser?.children(parentMediaId) ?? const [];

  @override
  Future<void> playFromMediaId(String mediaId,
          [Map<String, dynamic>? extras]) async =>
      browser?.playFromMediaId(mediaId);

  @override
  Future<void> playFromSearch(String query,
          [Map<String, dynamic>? extras]) async =>
      browser?.playFromSearch(query);

  @override
  Future<List<MediaItem>> search(String query,
          [Map<String, dynamic>? extras]) async =>
      await browser?.searchItems(query) ?? const [];

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    _customActionController.add(name);
  }

  /// Retourne false si le chargement echoue apres toutes les tentatives
  /// (appelant responsable de reagir -- voir PlayerController._advanceQueue, qui
  /// saute au titre suivant plutot que de rester bloque en silence).
  @override
  Future<bool> loadAndPlay(
    List<MediaItem> items,
    int startIndex, {
    Duration crossfade = Duration.zero,
    double gain = 1.0,
  }) async {
    queue.add(items);
    if (startIndex >= 0 && startIndex < items.length) {
      mediaItem.add(items[startIndex]);
    }

    final engine = _deck;
    if (engine != null) {
      if (items.length == 1 && engine.isPreloaded(items.first.id)) {
        debugPrint('⏭️ Titre précharge : bascule'
            '${crossfade > Duration.zero ? ' en fondu (${crossfade.inSeconds}s)' : ''}');
        try {
          await engine.playPreloaded(fade: crossfade, gain: gain);
          return true;
        } catch (e) {
          // Platine prechargee dans un mauvais etat : chargement classique.
          debugPrint('❌ ERREUR bascule préchargée: $e');
        }
      }
      await engine.setTrackGain(gain);
    }

    final sources = items.map((item) {
      final source = _queueItem(item);
      debugPrint(
          // Le titre, pas item.id : pour un stream c'est l'URL avec jeton.
          '🎵 AUDIO SOURCE: ${item.title} isRemote=${source.isRemote}');
      return source;
    }).toList();

    // Un blip reseau mobile (Tailscale en exterieur) faisait echouer le
    // chargement du titre suivant une fois sur deux sans que rien ne le
    // rattrape : l'erreur etait juste journalisee, puis silencieusement
    // ignoree -- la lecture semblait "bloquee" jusqu'a ce que l'utilisateur
    // revienne relancer le titre a la main (retour testeur). Quelques
    // tentatives rapprochees laissent le temps a un reseau capricieux de
    // revenir avant d'abandonner pour de bon.
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _engine.setAudioSources(sources, initialIndex: startIndex);
        debugPrint('✅ AudioSource chargé, lecture...');
        // Pas de await : just_audio ne resout play() qu'a la FIN du titre
        // (ou a la pause). L'attendre gardait _playSingle/_advanceQueue/
        // _continueQueueAutomatically (donc son verrou _autoContinuing)
        // bloques pendant tout le titre auto-enchaine -- sa fin etait alors
        // ignoree et le lecteur se figeait apres le 2e titre.
        unawaited(_engine.play().catchError((Object e) {
          debugPrint('❌ ERREUR play(): $e');
        }));
        return true;
      } catch (e) {
        debugPrint('❌ ERREUR LECTURE (tentative $attempt/$maxAttempts): $e');
        if (attempt == maxAttempts) return false;
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    return false;
  }

  @override
  Future<bool> preload(MediaItem item, {double gain = 1.0}) async {
    final engine = _deck;
    // Moteur simple (reprise Bluetooth en arriere-plan) ou Chromecast : pas
    // de seconde platine, le titre suivant sera charge a la fin du titre en
    // cours.
    if (engine == null) return false;
    debugPrint('⏳ Préchargement: ${item.title}');
    return engine.preload(
      PlayerQueueItem(path: item.id, isRemote: item.id.startsWith('http')),
      gain: gain,
    );
  }

  @override
  void cancelPreload() => _deck?.cancelPreload();

  @override
  Future<void> setTrackGain(double gain) async =>
      await _deck?.setTrackGain(gain);

  static PlayerQueueItem _queueItem(MediaItem item) => PlayerQueueItem(
        path: item.id,
        isRemote: item.id.startsWith('http'),
        title: item.title,
        artist: item.artist,
        album: item.album,
        artUri: item.artUri,
      );

  // --- Sortie (appareil ou Chromecast) ------------------------------------

  @override
  PlayerEngine get localEngine {
    final engine = _engine;
    return engine is RoutedPlayerEngine ? engine.local : engine;
  }

  @override
  PlayerEngine get activeEngine {
    final engine = _engine;
    return engine is RoutedPlayerEngine ? engine.active : engine;
  }

  @override
  Future<void> switchOutput(PlayerEngine target, {bool resume = true}) async {
    final router = _engine;
    if (router is! RoutedPlayerEngine || identical(router.active, target)) {
      return;
    }
    final previous = router.active;
    final item = mediaItem.value;
    final hadSource = previous.hasSource;
    final position = previous.position;
    final wasPlaying = previous.playing;
    cancelPreload();
    try {
      await previous.pause();
    } catch (e) {
      // Chromecast deja perdue : rien a mettre en pause.
      debugPrint('Sortie precedente injoignable: $e');
    }
    router.route(target);
    if (item != null && hadSource) {
      try {
        await target.setAudioSources([_queueItem(item)], initialIndex: 0);
        if (position > Duration.zero) await target.seek(position);
        if (resume && wasPlaying) {
          unawaited(target.play().catchError((Object e) {
            debugPrint('❌ ERREUR play(): $e');
          }));
        }
      } finally {
        _pushState();
      }
    } else {
      _pushState();
    }
  }

  @override
  void adoptOutput(PlayerEngine engine) {
    final router = _engine;
    if (router is! RoutedPlayerEngine) return;
    router.route(engine);
    _pushState();
  }

  PlaybackState _transformState() {
    return PlaybackState(
      controls: [
        const MediaControl(
          androidIcon: 'drawable/ic_notification_add',
          label: 'Ajouter aux favoris',
          action: MediaAction.custom,
          customAction: CustomMediaAction(name: 'add_to_likes'),
        ),
        MediaControl.skipToPrevious,
        if (_engine.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [1, 2, 3],
      processingState: _engine.processingState,
      playing: _engine.playing,
      updatePosition: _engine.position,
      bufferedPosition: _engine.bufferedPosition,
      speed: _engine.speed,
      queueIndex: _engine.currentIndex,
    );
  }

  Future<void> updateNotificationColor(int color) async {
    final current = mediaItem.value;
    if (current == null) return;
    mediaItem.add(current.copyWith(
      extras: {
        ...?current.extras,
        'androidNotificationColor': color,
      },
    ));
  }

  Future<void> toggleShuffle() async {
    await _engine.setShuffleModeEnabled(!_engine.shuffleModeEnabled);
  }

  bool get isShuffled => _engine.shuffleModeEnabled;

  Future<void> setLoopMode(LoopMode mode) async {
    await _engine.setLoopMode(mode);
  }

  LoopMode get loopMode => _engine.loopMode;
}
