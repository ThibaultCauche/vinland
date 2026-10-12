import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/track_repository.dart';
import '../domain/queue.dart';
import '../models/track.dart';
import '../services/player_engine.dart';
import 'jam_playback.dart';

/// Lecture locale : titre en cours, play/pause, seek, passage au suivant
/// (fin de titre, titre injouable, filet de securite en fin de titre),
/// lecture aleatoire/repetition et sauvegarde de l'etat de lecture.
///
/// Ne connait ni le Jam ni la synchro perso : JamController le pilote a
/// travers JamPlayback, AppState lui demande avant chaque action si le Jam
/// la prend en charge et se branche sur les crochets (onPlayingChanged,
/// onTrackStarted...) pour diffuser l'etat. Le moteur et
/// la bibliotheque sont injectes (PlaybackOutput, TrackRepository) pour
/// pouvoir tester tout ca avec un faux moteur (voir test/fakes/).
class PlayerController extends ChangeNotifier implements JamPlayback {
  PlayerController({
    required PlaybackOutput output,
    required TrackRepository tracks,
    PlayQueue? queue,
  })  : _output = output,
        _tracks = tracks,
        _queue = queue ?? PlayQueue() {
    final engine = _output.player;
    // Position : mise a jour du champ SANS notifier. Rien dans l'UI ne lit
    // position (MiniPlayer/PlayerSlider pollent le player directement) :
    // notifier ici reconstruisait TOUS les ecrans abonnes a AppState ~2x/
    // seconde pendant la lecture, pour rien.
    _subs.add(engine.positionStream.listen((pos) {
      position = pos;
      _checkStall(pos);
    }));
    _subs.add(engine.durationStream.listen((dur) {
      if (dur != null && dur != duration) {
        duration = dur;
        _notify();
      }
    }));
    _subs.add(engine.playingStream.listen((playing) {
      // Ignore tant que le moteur n'a pas rattrape le dernier ordre manuel
      // (voir _setPlayingIntent) -- pas de fenetre de temps fixe : le
      // premier chargement reseau d'une session peut prendre plus ou moins
      // longtemps selon l'appareil/le reseau, un delai fixe finit toujours
      // par etre trop court sur l'un d'eux. Des qu'un evenement d'accord
      // arrive, on arrete d'ignorer -- une vraie interruption externe
      // (perte du focus audio, appel telephonique...) survenant APRES cet
      // accord est donc toujours prise en compte normalement.
      final contradictsManualIntent = _lastManualPlaybackIntent != null &&
          _lastManualPlaybackIntent != playing;
      if (!contradictsManualIntent) {
        _lastManualPlaybackIntent = null;
        if (playing != isPlaying) {
          isPlaying = playing;
          _notify();
          onPlayingChanged?.call();
        }
      }
      onEngineEvent?.call();
    }));
    // Le titre en cours est toujours pousse explicitement par _playSingle,
    // jamais deduit d'un index rapporte par le moteur (un seul titre a la
    // fois lui est confie) : cet evenement ne sert plus qu'a rediffuser.
    _subs.add(engine.currentIndexStream.listen((_) => onEngineEvent?.call()));
    // File terminee : au lieu de couper brutalement, on reboucle sur la
    // meme file (playlist/titres likes/album lances) plutot que de devier
    // vers un autre contenu (cf. le retour des beta testeurs : la lecture
    // "quittait" leur liste pour jouer des titres du meme artiste).
    _subs.add(engine.completedStream.listen((_) {
      unawaited(_continueQueueAutomatically());
    }));
  }

  final PlaybackOutput _output;
  final TrackRepository _tracks;
  final PlayQueue _queue;
  final List<StreamSubscription<Object?>> _subs = [];
  bool _disposed = false;

  /// Un titre va etre charge (couleur d'ambiance de sa pochette).
  void Function(Track track)? onTrackLoading;

  /// Un titre a bien demarre et l'etat de lecture est sauvegarde : mirroir
  /// "now playing", scrobble, prise d'hote de la synchro perso.
  void Function(Track track)? onTrackStarted;

  /// Vraie bascule lecture/pause rapportee par le moteur.
  void Function()? onPlayingChanged;

  /// Tout evenement lecture/index du moteur (rediffusion de l'etat en Jam).
  void Function()? onEngineEvent;

  @override
  Track? currentTrack;
  @override
  bool isPlaying = false;
  @override
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  // Geres ici (pas delegues au moteur audio, qui ne charge qu'un seul titre
  // a la fois -- voir _playSingle) pour melanger/reboucler notre propre file.
  bool isShuffled = false;
  LoopMode loopMode = LoopMode.off;
  bool get isRepeatEnabled => loopMode != LoopMode.off;

  /// Titres a venir (voir PlayQueue.upcoming, y compris pourquoi cette
  /// liste est exposee telle quelle).
  @override
  List<Track> get queue => _queue.upcoming;

  PlayerEngine get player => _output.player;
  bool get hasSource => _output.player.hasSource;

  /// Marque une bascule play/pause explicite de l'utilisateur, pour que le
  /// listener sur playingStream (voir le constructeur) puisse ignorer tout
  /// evenement "en retard" qui la contredirait tant qu'un evenement d'accord
  /// n'est pas arrive. Sur le tout premier titre charge dans une session, le
  /// moteur audio natif peut mettre du temps a emettre son evenement
  /// "playing=true" initial (chargement/warm-up du codec + 1re connexion
  /// reseau vers le NAS, plus lente qu'une reconnexion) -- si l'utilisateur a
  /// deja tape pause entre-temps, cet evenement en retard arrivait APRES le
  /// isPlaying = false pose par togglePlayPause() et l'ecrasait,
  /// desynchronisant le bouton de l'etat reel (l'audio, lui, etait bien en
  /// pause). Une premiere version (corrigee le 2026-09-15) utilisait une
  /// fenetre fixe de 700ms plutot qu'une vraie attente d'accord -- trop court
  /// pour le premier chargement reseau sur certains appareils/reseaux
  /// mobiles (retour utilisateur, 2026-09-17 : desync systematique au tout
  /// premier titre de chaque session, quel que soit le delai ecoule apres
  /// l'ouverture de l'app).
  bool? _lastManualPlaybackIntent;

  /// Incremente a chaque action qui va finir par appeler _setPlayingIntent
  /// (togglePlayPause, _playSingle) : permet a _setPlayingIntent de detecter
  /// qu'un appel est perime (une action plus recente l'a deja supplantee)
  /// et de s'auto-ignorer plutot que d'ecraser l'etat a tort. Necessaire en
  /// plus du filtre sur playingStream ci-dessus : celui-la ne protege que
  /// des evenements EN RETARD du moteur, pas du cas ou c'est l'appel a
  /// _setPlayingIntent lui-meme qui est en retard -- _playSingle est async
  /// (attend loadAndPlay, un appel reseau vers le NAS) et peut donc se
  /// resoudre APRES qu'un togglePlayPause() plus recent ait deja pose le bon
  /// isPlaying, ecrasant alors ce bon etat avec le sien, perime (retour
  /// utilisateur, 2026-09-17 : bouton reste bloque sur "lecture" apres une
  /// pause au tout premier titre d'une session, reseau mobile plus lent que
  /// d'habitude a etablir la connexion initiale vers le NAS).
  int _playbackActionSeq = 0;

  void _setPlayingIntent(bool value, int seq) {
    if (seq != _playbackActionSeq) return;
    isPlaying = value;
    _lastManualPlaybackIntent = value;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // --- Lecture ---------------------------------------------------------

  /// Lance `track` et construit la file a partir de `trackList` (le
  /// contexte -- album, playlist, titres likes, artiste...) : voir
  /// PlayQueue.start.
  @override
  Future<void> playTrack(Track track, {List<Track>? trackList}) async {
    _queue.start(track, trackList, shuffled: isShuffled);
    _consecutiveLoadFailures = 0;
    await _playSingle(track);
  }

  /// Charge et joue un seul titre dans le moteur audio, sans toucher a la
  /// file : c'est le point commun a playTrack, _advanceQueue, previous et
  /// togglePlayPause (reprise apres redemarrage de l'app). Retourne false si
  /// le moteur n'a pas reussi a charger le titre (voir _advanceQueue, qui
  /// saute au suivant plutot que de laisser la lecture bloquee en silence).
  Future<bool> _playSingle(Track track) async {
    final seq = ++_playbackActionSeq;
    currentTrack = track;
    final path = _tracks.offlinePath(track.id) ?? track.filePath!;
    final isRemote = path.startsWith('http');

    Uri? artUri;
    if (track.coverPath != null) {
      artUri = track.coverPath!.startsWith('http')
          ? Uri.parse(track.coverPath!)
          : Uri.file(track.coverPath!);
    }

    final item = MediaItem(
      id: path,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
      artUri: artUri,
      extras: {'isRemote': isRemote},
    );

    onTrackLoading?.call(track);
    _notify();
    await Future<void>.delayed(Duration.zero);
    final loaded = await _output.loadAndPlay([item], 0);
    _setPlayingIntent(loaded, seq);
    if (!loaded) {
      _notify();
      return false;
    }
    await _tracks.recordPlay(track.id);
    // Attend (contrairement aux autres sauvegardes, fire-and-forget) :
    // c'est la valeur relue par le resume Bluetooth headless
    // (bluetooth_resume_entrypoint.dart) quand Android a deja tue le
    // process principal -- un titre change juste avant que l'app soit
    // reclamee en arriere-plan pouvait laisser cette ecriture jamais flushee
    // sur le disque, et le resume Bluetooth relancait alors le titre
    // PRECEDENT (dernier vraiment ecrit) au lieu du bon (retour utilisateur,
    // 2026-09-15 : "je reviens sur la musique d'avant apres une pause
    // externe", reproduit surtout avec un appareil Bluetooth de confiance --
    // voiture/casque -- qui se reconnecte pendant que l'app est en pause en
    // arriere-plan).
    await _savePlaybackState();
    onTrackStarted?.call(track);
    _notify();
    return true;
  }

  /// Retourne false quand il a fallu recharger le titre (redemarrage de
  /// l'app : le mini-player affiche le dernier titre joue mais aucune
  /// source n'est encore chargee dans le moteur, et un simple play() sur un
  /// moteur vide ne fait rien), true pour une vraie bascule play/pause.
  @override
  bool togglePlayPause() {
    if (currentTrack != null && !_output.player.hasSource) {
      unawaited(_playSingle(currentTrack!));
      return false;
    }
    final seq = ++_playbackActionSeq;
    final newIntent = !isPlaying;
    if (isPlaying) {
      unawaited(_output.pause());
    } else {
      unawaited(_output.play());
    }
    _setPlayingIntent(newIntent, seq);
    _notify();
    return true;
  }

  @override
  void seek(Duration pos) {
    unawaited(_output.seek(pos));
    _notify();
  }

  @override
  Future<void> next() => _advanceQueue();

  /// Avant 3s de lecture : revient au titre precedent (file d'attente
  /// remise en tete). Au-dela : redemarre simplement le titre en cours,
  /// comme la plupart des lecteurs.
  @override
  Future<void> previous() async {
    if (position > const Duration(seconds: 3) || !_queue.hasHistory) {
      seek(Duration.zero);
      return;
    }
    await _playSingle(_queue.back(currentTrack)!);
  }

  Future<void> playFromQueue(int index) async {
    final target = _queue.skipTo(index, currentTrack);
    if (target != null) await _playSingle(target);
  }

  // --- Fin de titre ----------------------------------------------------

  bool _autoContinuing = false;

  // Filet de securite : sur certains appareils Android, en arriere-plan
  // (ecran eteint, telephone en poche en exterieur), le processingState
  // just_audio n'atteint parfois jamais `completed` en fin de titre -- rien
  // ne declenche alors _continueQueueAutomatically et la lecture reste
  // bloquee, position figee en fin de titre, jusqu'a ce qu'on relance a la
  // main (retour testeur). Des qu'on approche de la fin, on arme un minuteur
  // qui force le passage au titre suivant si rien n'a bouge 2s plus tard --
  // annule/reutilise en boucle sinon, donc sans effet en fonctionnement
  // normal (completedStream a largement le temps de faire avancer la file
  // avant que ce filet ne se declenche).
  Timer? _stallWatchdog;

  void _checkStall(Duration pos) {
    // Comme dans _SeekBar (desktop) : la duree rapportee par le moteur
    // audio peut etre fausse/trop courte en debut de lecture d'un flux
    // Navidrome sans Content-Length (elle "grimpe" par paliers) -- s'y fier
    // ici declenchait ce filet bien avant la vraie fin et redemarrait le
    // titre depuis 0 (retour testeur). La duree des metadonnees du titre
    // est fiable des le debut, on la prefere. pos > 3s ecarte en plus toute
    // lecture a peine demarree d'un declenchement immediat.
    final track = currentTrack;
    final dur = (track != null && track.duration.inMilliseconds > 0)
        ? track.duration
        : duration;
    final nearEnd = isPlaying &&
        dur.inMilliseconds > 0 &&
        pos.inMilliseconds > 3000 &&
        (dur - pos).inMilliseconds < 800;
    if (!nearEnd) {
      _stallWatchdog?.cancel();
      _stallWatchdog = null;
      return;
    }
    if (_stallWatchdog != null) return; // deja arme pour ce titre
    final stalledTrackId = currentTrack?.id;
    final armedPosition = pos;
    _stallWatchdog = Timer(const Duration(seconds: 2), () {
      _stallWatchdog = null;
      // Un vrai blocage laisse la position figee. La duree metadonnee ID3
      // reste parfois sous-estimee meme apres avoir prefere celle-ci a
      // celle du moteur (bibliotheque en partie rippee depuis YouTube, voir
      // les notes de known-issues) : si la position a quand meme avance
      // depuis l'armement, le titre joue normalement au-dela de sa duree
      // annoncee -- ne pas le couper/redemarrer a tort (retour testeur :
      // "le titre redemarre de 0 vers la fin").
      final stillStalled = (position - armedPosition).inMilliseconds < 300;
      if (stillStalled && isPlaying && currentTrack?.id == stalledTrackId) {
        unawaited(_continueQueueAutomatically());
      }
    });
  }

  Future<void> _continueQueueAutomatically() async {
    if (_autoContinuing || _disposed) return;
    _autoContinuing = true;
    try {
      if (loopMode == LoopMode.one) {
        if (currentTrack != null) await _playSingle(currentTrack!);
        return;
      }
      await _advanceQueue();
    } finally {
      _autoContinuing = false;
    }
  }

  /// Nombre de titres consecutifs qu'on a du sauter faute d'avoir reussi a
  /// les charger (voir _advanceQueue) -- protege contre une boucle infinie
  /// si le reseau est completement coupe (sinon chaque titre de la file
  /// echouerait et relancerait immediatement le suivant, sans jamais
  /// s'arreter).
  int _consecutiveLoadFailures = 0;
  static const _maxConsecutiveLoadFailures = 3;

  /// Passe au titre suivant de la file (regeneree depuis le contexte lance
  /// si elle est vide, voir PlayQueue.advance).
  Future<void> _advanceQueue() async {
    final next = _queue.advance(currentTrack, shuffled: isShuffled);
    if (next == null) return;
    final loaded = await _playSingle(next);
    if (!loaded) {
      // Titre injouable (reseau/fichier) : plutot que de rester bloque en
      // silence dessus (le bug remonte par un testeur en exterieur), on
      // passe au suivant -- sauf si plusieurs echecs de suite suggerent que
      // le reseau est totalement coupe, auquel cas on abandonne pour de bon
      // au lieu de vider toute la file d'attente en boucle.
      _consecutiveLoadFailures++;
      if (_consecutiveLoadFailures < _maxConsecutiveLoadFailures) {
        await _advanceQueue();
      }
      return;
    }
    _consecutiveLoadFailures = 0;
  }

  // --- File d'attente --------------------------------------------------

  @override
  void addToQueue(Track track) {
    _queue.add(track);
    _queueChanged();
  }

  @override
  void playNext(Track track) {
    _queue.insertNext(track);
    _queueChanged();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.upcoming.length) return;
    _queue.removeAt(index);
    _queueChanged();
  }

  /// Reordonnancement par glisser-deposer (voir QueueScreen) : voir
  /// PlayQueue.reorder pour la convention de `newIndex`.
  void reorderQueue(int oldIndex, int newIndex) {
    _queue.reorder(oldIndex, newIndex);
    _queueChanged();
  }

  void _queueChanged() {
    unawaited(_savePlaybackState());
    _notify();
  }

  /// File de l'hote recue en Jam : remplace la notre telle quelle.
  @override
  void replaceQueue(List<Track> tracks) {
    _queue.replaceUpcoming(tracks);
    _notify();
  }

  /// Suivi d'un hote de Jam : aligne lecture/pause sur lui.
  @override
  Future<void> setPlaying(bool playing) async {
    if (playing && !isPlaying) {
      await _output.play();
    } else if (!playing && isPlaying) {
      await _output.pause();
    }
  }

  /// Bascule le mode aleatoire (voir PlayQueue.reshuffle : les titres
  /// ajoutes a la main restent en tete, inchanges).
  Future<void> toggleShuffle() async {
    isShuffled = !isShuffled;
    _queue.reshuffle(shuffled: isShuffled, current: currentTrack);
    unawaited(_saveShuffleLoopState());
    _notify();
  }

  Future<void> toggleLoopMode() async {
    loopMode = {
      LoopMode.off: LoopMode.all,
      LoopMode.all: LoopMode.one,
      LoopMode.one: LoopMode.off,
    }[loopMode]!;
    unawaited(_saveShuffleLoopState());
    _notify();
  }

  // --- Sauvegarde ------------------------------------------------------

  // Derniere lecture (mini-player) + lecture aleatoire/repetition :
  // memorises pour survivre a un redemarrage de l'app.
  static const _keyLastTrackId = 'vinland_last_track_id';
  static const _keyLastQueueIds = 'vinland_last_queue_ids';
  static const _keyLastSourceIds = 'vinland_last_source_ids';
  static const _keyLastQueueIndex = 'vinland_last_queue_index';
  static const _keyShuffleEnabled = 'vinland_shuffle_enabled';
  static const _keyLoopMode = 'vinland_loop_mode';

  /// Recharge le dernier titre joue (pour l'affichage dans le mini-player,
  /// sans relancer la lecture automatiquement) ainsi que les modes lecture
  /// aleatoire/repetition, a partir de la bibliotheque deja chargee depuis
  /// le cache local (pas besoin d'attendre la sync Navidrome).
  Future<void> restore(SharedPreferences prefs) async {
    isShuffled = prefs.getBool(_keyShuffleEnabled) ?? false;
    final loopName = prefs.getString(_keyLoopMode);
    if (loopName != null) {
      loopMode = LoopMode.values
          .firstWhere((m) => m.name == loopName, orElse: () => LoopMode.off);
    }

    final lastTrackId = prefs.getString(_keyLastTrackId);
    if (lastTrackId == null) return;
    final track = _tracks.findById(lastTrackId);
    if (track == null) return;

    final queueIds = prefs.getStringList(_keyLastQueueIds) ?? [];
    final sourceIds =
        prefs.getStringList(_keyLastSourceIds) ?? [lastTrackId, ...queueIds];
    _queue.restore(
      upcoming: queueIds.map(_tracks.findById).whereType<Track>().toList(),
      source: sourceIds.map(_tracks.findById).whereType<Track>().toList(),
    );
    currentTrack = track;
    onTrackLoading?.call(track);
    // isPlaying reste false : on affiche juste le dernier titre, on ne
    // relance pas un flux reseau tant que l'utilisateur n'a pas appuye play.
  }

  Future<void> _savePlaybackState() async {
    if (currentTrack == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastTrackId, currentTrack!.id);
    await prefs.setStringList(
        _keyLastQueueIds, _queue.upcoming.map((t) => t.id).toList());
    await prefs.setStringList(
        _keyLastSourceIds, _queue.sourceOrder.map((t) => t.id).toList());
  }

  Future<void> _saveShuffleLoopState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShuffleEnabled, isShuffled);
    await prefs.setString(_keyLoopMode, loopMode.name);
  }

  /// La coupure du lecteur passe par un canal de plateforme (audio_service) :
  /// si le service audio est dans un mauvais etat (ex: coupure reseau au NAS,
  /// foreground service tue par l'OS), cet appel peut planter ou rester
  /// bloque indefiniment. Ne doit jamais empecher une deconnexion : tente
  /// avec un timeout, sans jamais propager d'erreur.
  Future<void> stopOutput() async {
    try {
      await _output.stop().timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('PlayerController: stop() a echoue/timeout: $e');
    }
  }

  /// Oublie tout (deconnexion) : titre, file, historique et etat sauvegarde.
  Future<void> reset() async {
    currentTrack = null;
    isPlaying = false;
    _queue.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastTrackId);
    await prefs.remove(_keyLastQueueIds);
    await prefs.remove(_keyLastSourceIds);
    await prefs.remove(_keyLastQueueIndex);
    await prefs.remove(_keyShuffleEnabled);
    await prefs.remove(_keyLoopMode);
  }

  @override
  void dispose() {
    _disposed = true;
    _stallWatchdog?.cancel();
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }
}
