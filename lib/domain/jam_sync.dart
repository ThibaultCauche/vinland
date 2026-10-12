import 'dart:math' as math;

// Synchro fine du Jam entre amis : horloge commune (temps du relais) et
// decision de correction a chaque etat recu de l'hote. Pur Dart, sans
// reseau ni lecteur, pour etre teste tel quel (test/domain/jam_sync_test.dart).

/// Une mesure ping/pong avec le relais, facon NTP : [sentMs] et
/// [receivedMs] sont lus sur l'horloge locale, [relayMs] est l'heure du
/// relais au moment ou il a repondu.
class ClockSample {
  const ClockSample({
    required this.sentMs,
    required this.relayMs,
    required this.receivedMs,
  });

  final int sentMs;
  final int relayMs;
  final int receivedMs;

  /// Aller-retour reseau complet.
  int get roundTripMs => receivedMs - sentMs;

  /// Ce qu'il faut ajouter a l'heure locale pour obtenir celle du relais,
  /// en supposant l'aller aussi long que le retour (meme hypothese que
  /// NTP : l'erreur est au plus la moitie de l'ecart aller/retour).
  int get offsetMs => relayMs - (sentMs + receivedMs) ~/ 2;
}

/// Ecart estime entre l'horloge locale et celle du relais.
class ClockEstimate {
  const ClockEstimate({required this.offsetMs, required this.roundTripMs});

  /// Horloges jamais synchronisees (relais ancien qui ne repond pas aux
  /// pings) : on retombe sur l'ancien comportement, horloges supposees
  /// egales.
  static const unknown = ClockEstimate(offsetMs: 0, roundTripMs: -1);

  final int offsetMs;

  /// Aller-retour median des mesures retenues, -1 si inconnu (journal).
  final int roundTripMs;

  bool get isKnown => roundTripMs >= 0;

  /// Mediane des mesures plutot que moyenne : une seule mesure prise
  /// pendant un pic reseau (Wi-Fi charge en soiree, 4G) fausserait toute
  /// la moyenne de plusieurs centaines de ms.
  static ClockEstimate fromSamples(List<ClockSample> samples) {
    if (samples.isEmpty) return unknown;
    return ClockEstimate(
      offsetMs: _median(samples.map((s) => s.offsetMs)),
      roundTripMs: _median(samples.map((s) => s.roundTripMs)),
    );
  }
}

int _median(Iterable<int> values) {
  final sorted = values.toList()..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) ~/ 2;
}

/// Ce que fait le participant pour se recaler sur l'hote.
sealed class SyncAction {
  const SyncAction();
}

/// Assez proche : vitesse normale, rien d'autre.
class SyncHold extends SyncAction {
  const SyncHold();
}

/// Trop loin pour rattraper en douceur : saut direct a [target].
class SyncSeek extends SyncAction {
  const SyncSeek(this.target);
  final Duration target;
}

/// Ecart moyen : lecture legerement acceleree (> 1) ou ralentie (< 1) le
/// temps de rattraper, inaudible contrairement a un seek qui coupe le son
/// (et relance une requete sur un flux distant).
class SyncNudge extends SyncAction {
  const SyncNudge(this.speed);
  final double speed;
}

/// Seuils de correction (voir decideSync).
class SyncPolicy {
  const SyncPolicy({
    this.seekAbove = const Duration(seconds: 1),
    this.holdBelow = const Duration(milliseconds: 40),
    this.maxSpeedChange = 0.03,
    this.catchUpOver = const Duration(seconds: 4),
  });

  /// Au-dela : seek. Un rattrapage a 3 % prendrait plus de 30 s.
  final Duration seekAbove;

  /// En dessous : rien. Une quarantaine de ms ne s'entend pas entre deux
  /// enceintes d'une meme piece, et la position lue sur le lecteur n'est
  /// de toute facon pas plus precise que ca.
  final Duration holdBelow;

  /// Variation de vitesse maximale (3 % : a peine perceptible sur la
  /// hauteur du son, et media_kit/ExoPlayer corrigent la hauteur).
  final double maxSpeedChange;

  /// Temps vise pour resorber l'ecart : 200 ms d'avance donnent 5 % sur
  /// 4 s, ramenes a 3 % ; 60 ms donnent 1,5 %. Recalcule a chaque
  /// battement, donc la vitesse redescend au fur et a mesure.
  final Duration catchUpOver;
}

/// Decision a partir de l'ecart [drift] = position attendue (celle de
/// l'hote, transit et decalage manuel compris) - position locale. Positif :
/// on est en retard, il faut accelerer.
SyncAction decideSync(
  Duration drift, {
  required Duration expected,
  SyncPolicy policy = const SyncPolicy(),
}) {
  final ms = drift.inMicroseconds.abs() / 1000;
  if (ms > policy.seekAbove.inMilliseconds) return SyncSeek(expected);
  if (ms < policy.holdBelow.inMilliseconds) return const SyncHold();
  final wanted =
      drift.inMicroseconds / policy.catchUpOver.inMicroseconds; // relatif
  final change =
      wanted.clamp(-policy.maxSpeedChange, policy.maxSpeedChange).toDouble();
  return SyncNudge(1 + change);
}

/// Une ligne du journal de synchro (ecran cache, voir JamSyncDebugScreen) :
/// de quoi verifier a l'oreille ET en chiffres que deux appareils restent
/// alignes.
class SyncLogEntry {
  const SyncLogEntry({
    required this.at,
    required this.driftMs,
    required this.action,
    required this.clockOffsetMs,
    required this.roundTripMs,
  });

  final DateTime at;
  final int driftMs;
  final SyncAction action;
  final int clockOffsetMs;
  final int roundTripMs;

  String get actionLabel => switch (action) {
        SyncHold() => 'rien',
        SyncSeek(:final target) => 'seek ${target.inMilliseconds} ms',
        SyncNudge(:final speed) =>
          'vitesse ${((speed - 1) * 100).toStringAsFixed(1)} %',
      };
}

/// Dernieres mesures seulement : sur 10 minutes a un battement toutes les
/// 2 s, 300 lignes suffisent pour tout revoir.
class SyncLog {
  SyncLog({this.capacity = 300});

  final int capacity;
  final List<SyncLogEntry> _entries = [];

  List<SyncLogEntry> get entries => List.unmodifiable(_entries);

  void add(SyncLogEntry entry) {
    _entries.add(entry);
    if (_entries.length > capacity) _entries.removeAt(0);
  }

  void clear() => _entries.clear();

  /// Ecart absolu moyen sur les [last] dernieres mesures, en ms.
  double? averageAbsDriftMs({int last = 30}) {
    if (_entries.isEmpty) return null;
    final recent = _entries.sublist(math.max(0, _entries.length - last));
    return recent.map((e) => e.driftMs.abs()).reduce((a, b) => a + b) /
        recent.length;
  }
}
