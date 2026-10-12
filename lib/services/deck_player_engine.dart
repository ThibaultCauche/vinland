import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';

import 'player_engine.dart';

/// Deux moteurs audio (deux « platines ») presentes comme un seul.
///
/// Le moteur ne recoit toujours qu'UN titre a la fois (voir
/// PlayerController._playSingle : lui confier la file entiere rejouait le bug
/// de shuffle natif). Mais charger ce titre seulement a la fin du precedent
/// laissait un blanc a chaque changement : nouvelle requete vers le NAS,
/// mise en tampon, demarrage du decodeur -- plusieurs secondes en 4G, au
/// pire moment en soiree. Ici, pendant que la platine active joue, l'autre
/// prepare deja le titre suivant ([preload]) : au changement de titre il n'y
/// a plus qu'a basculer ([playPreloaded]), eventuellement en fondu.
///
/// Les ecouteurs (PlayerController, VinlandAudioHandler, barres de lecture)
/// ne voient que la platine active : la fin, l'arret ou la pause de la
/// platine sortante n'arrivent jamais jusqu'a eux, sinon la fin du titre
/// sortant ferait avancer la file une seconde fois.
class DeckPlayerEngine implements PlayerEngine {
  DeckPlayerEngine(
    PlayerEngine first,
    PlayerEngine second, {
    this.fadeTick = const Duration(milliseconds: 50),
  }) : _decks = [first, second] {
    _listen(0);
    _listen(1);
  }

  final List<PlayerEngine> _decks;

  /// Pas de la rampe de volume du fondu.
  final Duration fadeTick;

  int _active = 0;
  PlayerEngine get _current => _decks[_active];
  int get _idle => 1 - _active;

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _index = StreamController<int?>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];

  void _listen(int deck) {
    final engine = _decks[deck];
    void forward<T>(Stream<T> source, StreamController<T> target) {
      _subs.add(source.listen(
        (value) {
          if (deck == _active) target.add(value);
        },
        onError: (Object e, StackTrace st) {
          if (deck == _active) target.addError(e, st);
        },
      ));
    }

    forward(engine.positionStream, _position);
    forward(engine.durationStream, _duration);
    forward(engine.playingStream, _playing);
    forward(engine.currentIndexStream, _index);
    forward(engine.completedStream, _completed);
    // Les erreurs de la platine qui precharge sont gardees pour les logs :
    // c'est la que se voit un titre suivant injouable avant qu'il ne joue.
    _subs.add(engine.errorMessages.listen((msg) {
      _errors.add(deck == _active ? msg : 'prechargement: $msg');
    }));
  }

  // --- Volume -----------------------------------------------------------
  //
  // Trois facteurs multiplies par platine : le volume choisi par
  // l'utilisateur (curseur desktop, commun aux deux), le gain ReplayGain du
  // titre charge, et la position dans le fondu.

  double _master = 1.0;
  final List<double> _gain = [1.0, 1.0];
  final List<double> _fade = [1.0, 1.0];

  Future<void> _applyVolume(int deck) async {
    try {
      await _decks[deck].setVolume(_master * _gain[deck] * _fade[deck]);
    } catch (_) {
      // Moteur en cours d'arret/liberation : le volume sera repose au
      // prochain chargement.
    }
  }

  /// Gain ReplayGain (0..1) du titre de la platine active.
  Future<void> setTrackGain(double gain) async {
    _gain[_active] = gain;
    await _applyVolume(_active);
  }

  // --- Prechargement ----------------------------------------------------

  String? _preloadPath;
  bool _preloadReady = false;
  int _preloadSeq = 0;

  /// Vrai si [path] est charge sur la platine inactive, pret a jouer.
  bool isPreloaded(String path) => _preloadReady && _preloadPath == path;

  /// Charge [item] sur la platine inactive, en pause, sans toucher a celle
  /// qui joue. Retourne false si le chargement echoue ou a ete annule
  /// entre-temps (le titre sera alors charge normalement le moment venu).
  Future<bool> preload(PlayerQueueItem item, {double gain = 1.0}) async {
    if (_preloadPath == item.path) return _preloadReady;
    final seq = ++_preloadSeq;
    // Titre tres court : la platine inactive peut encore finir le fondu
    // precedent.
    _finishFade();
    final deck = _idle;
    _preloadPath = item.path;
    _preloadReady = false;
    _gain[deck] = gain;
    _fade[deck] = 1.0;
    await _applyVolume(deck);
    try {
      await _decks[deck].setAudioSources([item], initialIndex: 0);
    } catch (e) {
      if (seq == _preloadSeq) _preloadPath = null;
      _errors.add('prechargement: $e');
      return false;
    }
    if (seq != _preloadSeq || deck != _idle) return false;
    _preloadReady = true;
    return true;
  }

  /// Oublie le titre precharge (la file a change, ce n'est plus lui le
  /// suivant).
  void cancelPreload() {
    _preloadSeq++;
    if (_preloadPath == null) return;
    _preloadPath = null;
    _preloadReady = false;
    if (_fadeTimer == null) unawaited(_silence(_idle));
  }

  /// Bascule sur le titre precharge. Avec [fade] > 0, les deux titres se
  /// chevauchent pendant ce temps (rampe de volume a puissance constante :
  /// pas de creux de volume au milieu du fondu).
  Future<void> playPreloaded({
    Duration fade = Duration.zero,
    double gain = 1.0,
  }) async {
    _finishFade();
    final outgoing = _active;
    final incoming = _idle;
    final outgoingWasPlaying = _decks[outgoing].playing;
    _preloadSeq++;
    _preloadPath = null;
    _preloadReady = false;

    _active = incoming;
    _gain[incoming] = gain;
    // Etat de la nouvelle platine pour les ecouteurs : elle n'a rien
    // emis tant qu'elle etait inactive.
    final engine = _decks[incoming];
    _duration.add(engine.duration);
    _index.add(engine.currentIndex);
    _position.add(engine.position);

    final crossfade = fade > Duration.zero && outgoingWasPlaying;
    _fade[incoming] = crossfade ? 0.0 : 1.0;
    await _applyVolume(incoming);
    // Pas de await : just_audio ne resout play() qu'a la fin du titre (voir
    // VinlandAudioHandler.loadAndPlay).
    unawaited(engine.play().catchError((Object e) {
      _errors.add('play: $e');
    }));
    if (crossfade) {
      _startFade(outgoing, incoming, fade);
    } else {
      await _silence(outgoing);
    }
  }

  // --- Fondu ------------------------------------------------------------

  Timer? _fadeTimer;
  int? _fadingOut;

  void _startFade(int from, int to, Duration fade) {
    _fadingOut = from;
    final steps = math.max(1, fade.inMilliseconds ~/ fadeTick.inMilliseconds);
    var step = 0;
    _fadeTimer = Timer.periodic(fadeTick, (_) {
      step++;
      final t = math.min(1.0, step / steps);
      _fade[to] = math.sin(t * math.pi / 2);
      _fade[from] = math.cos(t * math.pi / 2);
      unawaited(_applyVolume(to));
      unawaited(_applyVolume(from));
      if (step >= steps) _finishFade();
    });
  }

  /// Termine tout de suite un fondu en cours : titre entrant a plein
  /// volume, titre sortant arrete. Appele avant toute action qui change
  /// la lecture (pause, autre titre, seek...) pour ne jamais laisser deux
  /// titres jouer en meme temps hors d'un fondu.
  void _finishFade() {
    final timer = _fadeTimer;
    if (timer == null) return;
    timer.cancel();
    _fadeTimer = null;
    final from = _fadingOut!;
    _fadingOut = null;
    _fade[_active] = 1.0;
    unawaited(_applyVolume(_active));
    unawaited(_silence(from));
  }

  bool get isFading => _fadeTimer != null;

  Future<void> _silence(int deck) async {
    try {
      await _decks[deck].stop();
    } catch (_) {}
    _fade[deck] = 1.0;
    await _applyVolume(deck);
  }

  // --- PlayerEngine -----------------------------------------------------

  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<int?> get currentIndexStream => _index.stream;
  @override
  Stream<void> get completedStream => _completed.stream;
  @override
  Stream<String> get errorMessages => _errors.stream;

  @override
  Duration get position => _current.position;
  @override
  Duration? get duration => _current.duration;
  @override
  Duration get bufferedPosition => _current.bufferedPosition;
  @override
  double get speed => _current.speed;

  /// Volume choisi par l'utilisateur, sans le gain ReplayGain ni le fondu.
  @override
  double get volume => _master;
  @override
  bool get playing => _current.playing;
  @override
  int? get currentIndex => _current.currentIndex;
  @override
  bool get hasSource => _current.hasSource;
  @override
  bool get shuffleModeEnabled => _current.shuffleModeEnabled;
  @override
  LoopMode get loopMode => _current.loopMode;
  @override
  AudioProcessingState get processingState => _current.processingState;

  /// Chargement classique (titre non precharge : lancement depuis un
  /// album, precedent, file modifiee au dernier moment...) : sur la
  /// platine active, l'autre est liberee.
  @override
  Future<void> setAudioSources(
    List<PlayerQueueItem> items, {
    required int initialIndex,
  }) async {
    _finishFade();
    if (_preloadPath != null) cancelPreload();
    _fade[_active] = 1.0;
    await _applyVolume(_active);
    await _current.setAudioSources(items, initialIndex: initialIndex);
  }

  @override
  Future<void> play() => _current.play();

  @override
  Future<void> pause() {
    _finishFade();
    return _current.pause();
  }

  @override
  Future<void> stop() async {
    _finishFade();
    cancelPreload();
    await Future.wait([
      _decks[0].stop(),
      _decks[1].stop(),
    ]);
  }

  @override
  Future<void> seek(Duration position) {
    _finishFade();
    return _current.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    _master = volume.clamp(0.0, 1.0);
    await Future.wait([_applyVolume(0), _applyVolume(1)]);
  }

  @override
  Future<void> seekToNext() => _current.seekToNext();
  @override
  Future<void> seekToPrevious() => _current.seekToPrevious();

  @override
  Future<void> setShuffleModeEnabled(bool enabled) => Future.wait([
        _decks[0].setShuffleModeEnabled(enabled),
        _decks[1].setShuffleModeEnabled(enabled),
      ]);

  @override
  Future<void> setLoopMode(LoopMode mode) => Future.wait([
        _decks[0].setLoopMode(mode),
        _decks[1].setLoopMode(mode),
      ]);

  @override
  Future<void> dispose() async {
    _fadeTimer?.cancel();
    for (final sub in _subs) {
      await sub.cancel();
    }
    await Future.wait([_decks[0].dispose(), _decks[1].dispose()]);
    for (final c in [_position, _duration, _playing, _index, _completed]) {
      await c.close();
    }
    await _errors.close();
  }
}
