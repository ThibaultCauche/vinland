import 'dart:math' as math;

/// Transforme les niveaux bruts remontes par l'analyse audio (basses et
/// mediums, 0..1) en ce que dessine le visuel du lecteur : un niveau lisse
/// et les « coups » (grosse caisse, basse qui tape) qui lancent une vague.
///
/// Les niveaux bruts dependent beaucoup du morceau (un titre masterise fort
/// sature, un morceau acoustique reste bas) : on les rapporte au plus haut
/// niveau recent, qui redescend lentement, pour que le visuel bouge autant
/// sur les deux.
class BeatPulse {
  BeatPulse({
    this.minBeatGap = const Duration(milliseconds: 280),
    this.beatRatio = 1.35,
    this.minBeatLevel = 0.18,
  });

  /// Deux coups plus rapproches que ca n'en font qu'un (≈ 210 BPM max).
  final Duration minBeatGap;

  /// Un coup = basses au-dessus de [beatRatio] fois leur moyenne recente.
  final double beatRatio;

  /// En dessous (niveau normalise), pas de coup : evite les vagues sur le
  /// souffle d'un passage calme.
  final double minBeatLevel;

  double _peak = 0.05;
  double _bassPeak = 0.05;
  double _bassAverage = 0;
  double _level = 0;
  Duration _sinceBeat = const Duration(days: 1);

  /// Niveau lisse 0..1 : monte vite, redescend doucement.
  double get level => _level;

  /// Ajoute une mesure ; [elapsed] = temps depuis la precedente. Renvoie la
  /// force du coup (0..1) si cette mesure en est un, sinon null.
  double? add({
    required double bass,
    required double mid,
    required Duration elapsed,
  }) {
    final dt = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    _sinceBeat += elapsed;

    final b = bass.clamp(0.0, 1.0);
    final raw = b * 0.75 + mid.clamp(0.0, 1.0) * 0.25;
    // Pics recents qui redescendent d'environ moitie toutes les 4 s.
    final decay = math.pow(0.84, dt).toDouble();
    _peak = math.max(raw, _peak * decay);
    _bassPeak = math.max(b, _bassPeak * decay);
    final normalized = _peak <= 0.02 ? 0.0 : (raw / _peak).clamp(0.0, 1.0);

    // Attaque rapide, relachement lent : le visuel suit le coup sans
    // clignoter.
    final k = normalized > _level ? 0.6 : 1 - math.pow(0.02, dt).toDouble();
    _level += (normalized - _level) * k.clamp(0.0, 1.0);

    final bassNorm = _bassPeak <= 0.02 ? 0.0 : b / _bassPeak;
    final isBeat = bassNorm >= minBeatLevel &&
        bassNorm > _bassAverage * beatRatio &&
        _sinceBeat >= minBeatGap;
    // Moyenne glissante sur ~0,5 s.
    final a = 1 - math.pow(0.0025, dt).toDouble();
    _bassAverage += (bassNorm - _bassAverage) * a.clamp(0.0, 1.0);

    if (!isBeat) return null;
    _sinceBeat = Duration.zero;
    return bassNorm;
  }

  void reset() {
    _peak = 0.05;
    _bassPeak = 0.05;
    _bassAverage = 0;
    _level = 0;
    _sinceBeat = const Duration(days: 1);
  }
}

/// Une vague qui part du centre du visuel.
class PulseRing {
  PulseRing(this.strength);

  final double strength;
  double age = 0;
}

/// Vagues en cours : chacune s'eloigne du centre et s'eteint.
class PulseRings {
  PulseRings({this.lifetime = 1.6, this.maxRings = 6});

  /// Duree de vie d'une vague, en secondes.
  final double lifetime;
  final int maxRings;

  final List<PulseRing> rings = [];

  void spawn(double strength) {
    rings.add(PulseRing(strength.clamp(0.0, 1.0)));
    if (rings.length > maxRings) rings.removeAt(0);
  }

  void advance(double seconds) {
    for (final r in rings) {
      r.age += seconds;
    }
    rings.removeWhere((r) => r.age >= lifetime);
  }

  /// Luminosite ajoutee par les vagues a une case situee a [distance]
  /// (0 = centre, 1 = bord le plus eloigne).
  double glowAt(double distance) {
    var glow = 0.0;
    for (final r in rings) {
      final t = r.age / lifetime;
      final front = t * 1.15;
      final d = (distance - front) / 0.16;
      glow += r.strength * (1 - t * t) * math.exp(-d * d);
    }
    return glow.clamp(0.0, 1.0);
  }
}
