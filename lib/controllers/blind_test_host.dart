import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/track.dart';
import '../services/matching_service.dart';
import '../services/party/party_models.dart';
import 'party_host_dj.dart';

/// Ce que le blind test demande au lecteur de l'hote.
abstract class BlindTestPlayback {
  /// Joue [track] a partir de [from].
  Future<void> playExtract(Track track, Duration from);
}

/// Ce que le blind test envoie au relais (voir PartyController).
abstract class BlindTestRelay {
  BlindTestState? get blindTest;
  void startBlindTest(int rounds);
  void sendBlindTestRound({
    required List<String> choices,
    required int answer,
    required Duration duration,
    required PartySong song,
  });
  void revealBlindTest();
  void stopBlindTest();
  void closeBlindTest();
}

/// Une manche preparee : le titre a faire deviner et les choix montres.
class BlindTestQuestion {
  const BlindTestQuestion(this.track, this.choices, this.answer);
  final Track track;
  final List<String> choices;
  final int answer;
}

/// Blind test cote hote : choisit les titres dans sa bibliotheque, prepare
/// 4 choix par manche (le bon titre et 3 leurres d'autres artistes, du meme
/// genre si possible), joue l'extrait et devoile la reponse au bout du
/// chrono. Le relais garde la reponse secrete et compte les points.
///
/// Pendant le blind test, le DJ de soiree est mis en pause : il ne place
/// plus la file des invites et n'annonce plus les titres (le titre en cours
/// donnerait la reponse sur les telephones et l'ecran d'ambiance).
class BlindTestHost extends ChangeNotifier {
  BlindTestHost({
    required this.relay,
    required this.playback,
    required this.library,
    required this.setDjSuspended,
    Random? random,
  }) : _random = random ?? Random();

  final BlindTestRelay relay;
  final BlindTestPlayback playback;
  final List<Track> Function() library;
  final void Function(bool suspended) setDjSuspended;
  final Random _random;

  static const choicesPerRound = 4;

  /// Assez de titres d'artistes differents pour faire des leurres.
  static const minArtists = choicesPerRound;

  List<BlindTestQuestion> _questions = const [];
  int _next = 0;
  Duration extract = const Duration(seconds: 20);
  Timer? _timer;
  bool _running = false;

  bool get isRunning => _running;
  int get roundsPlanned => _questions.length;
  bool get hasNextRound => _running && _next < _questions.length;

  /// Titre de la manche en cours (l'hote le voit, pas les invites).
  BlindTestQuestion? get current => _next == 0 ? null : _questions[_next - 1];

  /// Titres jouables pour un blind test : sur le NAS (les invites n'ont
  /// rien a telecharger), assez longs pour un extrait, un seul par titre.
  static List<Track> candidates(List<Track> library) {
    final seen = <String>{};
    return [
      for (final t in library)
        if (t.subsonicId != null &&
            t.duration >= const Duration(seconds: 60) &&
            seen.add(_key(t)))
          t
    ];
  }

  static String _key(Track t) =>
      '${MatchingService.normalize(t.artist)}|${MatchingService.normalize(t.title)}';

  static String _artistKey(Track t) => MatchingService.normalize(t.artist);

  /// Vrai si la bibliotheque permet un blind test.
  static bool canPlay(List<Track> library) =>
      candidates(library).map(_artistKey).toSet().length >= minArtists;

  /// Prepare [rounds] manches. Les titres deja ecoutes ou likes passent en
  /// premier : un blind test se gagne sur des titres qu'on connait.
  @visibleForTesting
  List<BlindTestQuestion> prepare(int rounds) {
    final pool = candidates(library());
    final known = pool.where((t) => t.playCount > 0 || t.isLiked).toList()
      ..shuffle(_random);
    final others = pool.where((t) => t.playCount == 0 && !t.isLiked).toList()
      ..shuffle(_random);
    final picks = <Track>[];
    final usedArtists = <String>{};
    // Un artiste par manche tant que possible : 10 manches de Daft Punk,
    // c'est trop facile.
    for (final pass in [true, false]) {
      for (final t in [...known, ...others]) {
        if (picks.length >= rounds) break;
        if (picks.contains(t)) continue;
        if (pass && !usedArtists.add(_artistKey(t))) continue;
        picks.add(t);
      }
    }
    return [for (final t in picks) _question(t, pool)];
  }

  BlindTestQuestion _question(Track track, List<Track> pool) {
    final artist = _artistKey(track);
    final decoyPool = pool.where((t) => _artistKey(t) != artist).toList()
      ..shuffle(_random);
    // Meme genre d'abord : des leurres trop differents trahissent la
    // reponse (un titre de rap au milieu de trois titres de classique).
    final genre = track.genre?.toLowerCase();
    decoyPool.sort((a, b) {
      final sa = a.genre?.toLowerCase() == genre ? 0 : 1;
      final sb = b.genre?.toLowerCase() == genre ? 0 : 1;
      return sa.compareTo(sb);
    });
    final decoys = <Track>[];
    final decoyArtists = <String>{};
    for (final t in decoyPool) {
      if (decoys.length >= choicesPerRound - 1) break;
      if (decoyArtists.add(_artistKey(t))) decoys.add(t);
    }
    final options = [track, ...decoys]..shuffle(_random);
    return BlindTestQuestion(
      track,
      [for (final t in options) label(t)],
      options.indexOf(track),
    );
  }

  /// « Titre · Artiste », comme dans la file de la soiree.
  static String label(Track t) => '${t.title} · ${t.artist}';

  /// Lance un blind test de [rounds] manches de [extract] chacune. False si
  /// la bibliotheque ne suffit pas.
  bool start(
      {int rounds = 10, Duration extract = const Duration(seconds: 20)}) {
    final questions = prepare(rounds);
    if (questions.isEmpty ||
        candidates(library()).map(_artistKey).toSet().length < minArtists) {
      return false;
    }
    _questions = questions;
    _next = 0;
    this.extract = extract;
    _running = true;
    setDjSuspended(true);
    relay.startBlindTest(questions.length);
    notifyListeners();
    return true;
  }

  /// Joue la manche suivante ; la reponse est devoilee a la fin du chrono.
  Future<void> nextRound() async {
    if (!hasNextRound) return;
    _timer?.cancel();
    final q = _questions[_next++];
    notifyListeners();
    await playback.playExtract(q.track, extractStart(q.track, extract));
    if (!_running) return;
    relay.sendBlindTestRound(
      choices: q.choices,
      answer: q.answer,
      duration: extract,
      song: partySongForTrack(q.track) ??
          PartySong(songId: '', title: q.track.title, artist: q.track.artist),
    );
    _timer = Timer(extract, reveal);
  }

  /// Ou commencer l'extrait : vers le tiers du titre (le refrain plutot
  /// que l'intro), sans depasser la fin.
  static Duration extractStart(Track track, Duration extract) {
    final total = track.duration;
    final latest = total - extract - const Duration(seconds: 5);
    if (latest <= Duration.zero) return Duration.zero;
    final third = total * 0.3;
    final start = third < const Duration(seconds: 90)
        ? third
        : const Duration(seconds: 90);
    return start > latest ? latest : start;
  }

  /// Devoile la reponse (avant la fin du chrono si tout le monde a repondu).
  void reveal() {
    _timer?.cancel();
    _timer = null;
    if (!_running) return;
    relay.revealBlindTest();
  }

  /// Fin du blind test : classement final, la soiree reprend son cours.
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (!_running) return;
    _running = false;
    relay.stopBlindTest();
    setDjSuspended(false);
    notifyListeners();
  }

  /// Referme le classement chez tout le monde.
  void close() {
    if (_running) stop();
    relay.closeBlindTest();
    _questions = const [];
    _next = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
