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
    this.beatRatio = 1.6,
    this.minBeatLevel = 0.05,
  });

  /// Deux coups plus rapproches que ca n'en font qu'un (≈ 210 BPM max).
  final Duration minBeatGap;

  /// Un coup = montee des basses au-dessus de [beatRatio] fois la montee
  /// moyenne recente.
  final double beatRatio;

  /// Montee minimale, en part du pic recent des basses : evite les vagues
  /// sur le souffle d'un passage calme.
  final double minBeatLevel;

  /// Les niveaux arrivent sur une echelle log (0..1, voir AudioVisualizer.kt)
  /// qui ecrase les coups : une basse continue y reste vers 0,85 et une
  /// grosse caisse monte a peine a 0,95. On repasse en lineaire (0..128)
  /// pour que la frappe ressorte.
  static final double _logScale = math.log(129);

  double _peak = 0.05;
  double _level = 0;
  double _lastBass = -1;
  double _lastMid = -1;
  double _bassLin = 0;
  double _linPeak = 1;
  double _riseAverage = 0;
  Duration _sinceSample = Duration.zero;
  Duration _sinceBeat = const Duration(days: 1);

  /// Niveau lisse 0..1 : monte vite, redescend doucement.
  double get level => _level;

  /// Ajoute une mesure ; [elapsed] = temps depuis la precedente. Renvoie la
  /// force du coup (0..1) si cette mesure en est un, sinon null.
  ///
  /// Peut etre appele a chaque image avec la meme mesure repetee (l'analyse
  /// en envoie une toutes les ~50 ms) : une valeur identique arrivee moins
  /// de 40 ms apres la precedente ne compte pas pour reperer les coups.
  double? add({
    required double bass,
    required double mid,
    required Duration elapsed,
  }) {
    final dt = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    _sinceBeat += elapsed;
    _sinceSample += elapsed;

    final b = bass.clamp(0.0, 1.0);
    final raw = b * 0.75 + mid.clamp(0.0, 1.0) * 0.25;
    // Pics recents qui redescendent d'environ moitie toutes les 4 s.
    _peak = math.max(raw, _peak * math.pow(0.84, dt).toDouble());
    final normalized = _peak <= 0.02 ? 0.0 : (raw / _peak).clamp(0.0, 1.0);

    // Attaque rapide, relachement lent : le visuel suit le coup sans
    // clignoter.
    final k = normalized > _level ? 0.6 : 1 - math.pow(0.02, dt).toDouble();
    _level += (normalized - _level) * k.clamp(0.0, 1.0);

    final fresh = bass != _lastBass ||
        mid != _lastMid ||
        _sinceSample >= const Duration(milliseconds: 40);
    _lastBass = bass;
    _lastMid = mid;
    if (!fresh) return null;
    final sampleDt =
        _sinceSample.inMicroseconds / Duration.microsecondsPerSecond;
    _sinceSample = Duration.zero;

    // Coup = brusque montee de l'energie des basses (pas leur niveau).
    final lin = math.exp(b * _logScale) - 1;
    final rise = math.max(0.0, lin - _bassLin);
    _bassLin = lin;
    _linPeak = math.max(lin, _linPeak * math.pow(0.84, sampleDt).toDouble());
    final isBeat = rise >= _linPeak * minBeatLevel &&
        rise > _riseAverage * beatRatio &&
        _sinceBeat >= minBeatGap;
    // Moyenne des montees sur ~1 s.
    final a = 1 - math.pow(0.05, sampleDt).toDouble();
    _riseAverage += (rise - _riseAverage) * a.clamp(0.0, 1.0);

    if (!isBeat) return null;
    _sinceBeat = Duration.zero;
    return (rise / (_linPeak * 0.5)).clamp(0.0, 1.0);
  }

  void reset() {
    _peak = 0.05;
    _level = 0;
    _lastBass = -1;
    _lastMid = -1;
    _bassLin = 0;
    _linPeak = 1;
    _riseAverage = 0;
    _sinceSample = Duration.zero;
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
      final d = (distance - front) / 0.22;
      glow += r.strength * (1 - t * t) * math.exp(-d * d);
    }
    return glow.clamp(0.0, 1.0);
  }
}
