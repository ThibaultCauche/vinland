import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'player_engine.dart';

/// Backend media_kit (libmpv) : utilise sur desktop (Windows/Linux), la ou
/// just_audio ne declare aucune implementation native.
class MediaKitPlayerEngine implements PlayerEngine {
  final mk.Player _player;
  bool _shuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;
  bool _hasSource = false;

  // Ordre "logique" (celui de AppState.queue au moment du chargement) des
  // URIs de la playlist chargee. setShuffle() (commande mpv
  // "playlist-shuffle", voir setAudioSources ci-dessous) reordonne l'ordre
  // INTERNE de mpv -- y compris quand on l'appelle en cours de lecture, sur
  // simple bascule du bouton "lecture aleatoire" -- sans jamais changer le
  // titre reellement en train de jouer. Si currentIndex renvoyait la
  // position brute mpv, AppState (qui associe index -> Track via son propre
  // AppState.queue, jamais reordonne, lui) affichait alors instantanement
  // la cover/le titre/l'artiste d'un AUTRE titre que celui qu'on entendait
  // reellement. just_audio n'a pas ce probleme : son shuffle ne touche
  // jamais a currentIndex, qui reste toujours la position dans la sequence
  // d'origine -- on reproduit ce meme contrat ici en retrouvant, a chaque
  // evenement, la position d'origine du titre reellement charge par mpv.
  final List<String> _logicalOrder = [];

  MediaKitPlayerEngine() : _player = mk.Player();

  int? _logicalIndexOf(mk.Playlist playlist) {
    if (!_hasSource) return null;
    if (playlist.index < 0 || playlist.index >= playlist.medias.length) {
      return null;
    }
    final uri = playlist.medias[playlist.index].uri;
    final logical = _logicalOrder.indexOf(uri);
    return logical == -1 ? playlist.index : logical;
  }

  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<Duration?> get durationStream => _player.stream.duration;
  @override
  Stream<bool> get playingStream => _player.stream.playing;
  @override
  Stream<int?> get currentIndexStream =>
      _player.stream.playlist.map(_logicalIndexOf);
  @override
  Stream<void> get completedStream =>
      _player.stream.completed.where((completed) => completed);
  @override
  Stream<String> get errorMessages => _player.stream.error;

  @override
  Duration get position => _player.state.position;
  @override
  Duration? get duration => _player.state.duration;
  @override
  Duration get bufferedPosition => _player.state.buffer;
  @override
  double get speed => _player.state.rate;
  @override
  double get volume => _player.state.volume / 100.0;
  @override
  bool get playing => _player.state.playing;
  @override
  int? get currentIndex =>
      _hasSource ? _logicalIndexOf(_player.state.playlist) : null;
  @override
  bool get hasSource => _hasSource;
  @override
  bool get shuffleModeEnabled => _shuffleEnabled;
  @override
  LoopMode get loopMode => _loopMode;
  @override
  AudioProcessingState get processingState => _player.state.buffering
      ? AudioProcessingState.buffering
      : (_player.state.playing
          ? AudioProcessingState.ready
          : AudioProcessingState.idle);

  @override
  Future<void> setAudioSources(
    List<PlayerQueueItem> items, {
    required int initialIndex,
  }) async {
    // Les pistes bundlees en assets Flutter (demo embarquee) ne sont pas
    // lisibles directement par libmpv (pas d'acces au bundle Flutter) --
    // limitation connue, non bloquante : usage reel = streaming Navidrome +
    // fichiers hors-ligne, jamais les assets de demo.
    final playable = items.where((i) => !i.isAsset).toList();
    if (playable.isEmpty) return;
    final adjustedIndex = initialIndex.clamp(0, playable.length - 1);
    final targetUri = mk.Media(playable[adjustedIndex].path).uri;

    final playlist = mk.Playlist(
      playable.map((i) => mk.Media(i.path)).toList(),
      index: adjustedIndex,
    );
    _logicalOrder
      ..clear()
      ..addAll(playlist.medias.map((m) => m.uri));
    await _player.open(playlist);
    await _player.setShuffle(_shuffleEnabled);
    // _player.open() positionne bien playlist-pos sur adjustedIndex, mais
    // setShuffle() (commande mpv "playlist-shuffle") reordonne ensuite la
    // playlist ENTIERE -- y compris la piste qu'on vient d'ouvrir -- ce qui
    // faisait sauter la lecture vers un titre aleatoire juste apres avoir
    // clique sur un titre precis, quand la lecture aleatoire etait active
    // (media_kit.Player.open() reinitialise toujours son shuffle interne a
    // false, donc setShuffle(true) juste apres n'est jamais un no-op et
    // relance systematiquement ce reordonnancement). On retrouve le titre
    // voulu dans le nouvel ordre et on s'y repositionne explicitement.
    if (_shuffleEnabled) {
      final shuffledIndex =
          _player.state.playlist.medias.indexWhere((m) => m.uri == targetUri);
      if (shuffledIndex != -1 &&
          shuffledIndex != _player.state.playlist.index) {
        await _player.jump(shuffledIndex);
      }
    }
    await _player.setPlaylistMode(_playlistModeFor(_loopMode));
    _hasSource = true;
  }

  mk.PlaylistMode _playlistModeFor(LoopMode mode) => switch (mode) {
        LoopMode.off => mk.PlaylistMode.none,
        LoopMode.one => mk.PlaylistMode.single,
        LoopMode.all => mk.PlaylistMode.loop,
      };

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume * 100.0);
  @override
  Future<void> seekToNext() => _player.next();
  @override
  Future<void> seekToPrevious() => _player.previous();

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    _shuffleEnabled = enabled;
    await _player.setShuffle(enabled);
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
    await _player.setPlaylistMode(_playlistModeFor(mode));
  }

  @override
  Future<void> dispose() => _player.dispose();
}
