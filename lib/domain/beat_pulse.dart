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
    this.minBeatBass = 0.78,
  });

  /// Deux coups plus rapproches que ca n'en font qu'un (≈ 210 BPM max).
  final Duration minBeatGap;

  /// Un coup = montee des basses au-dessus de [beatRatio] fois la montee
  /// moyenne recente.
  final double beatRatio;

  /// Montee minimale, en part du pic recent des basses : evite les vagues
  /// sur le souffle d'un passage calme.
  final double minBeatLevel;

  /// Basses minimales (echelle log 0..1) pour un coup : 0,85-1 sur une
  /// batterie, 0,3-0,6 sur un piano (mesure sur le telephone).
  final double minBeatBass;

  /// Les niveaux arrivent sur une echelle log (0..1, voir AudioVisualizer.kt)
  /// qui ecrase les coups : une basse continue y reste vers 0,85 et une
  /// grosse caisse monte a peine a 0,95. On repasse en lineaire (0..128)
  /// pour que la frappe ressorte.
  static final double _logScale = math.log(129);

  double _midPeak = 0.05;
  double _level = 0;
  double _lastBass = -1;
  double _lastMid = -1;
  double _bassLin = 0;
  double _linPeak = 1;
  double _riseAverage = 0;
  double _midLin = 0;
  double _midLinPeak = 1;
  double _loudPeak = 0;
  double _loud = 0;
  Duration _sinceSample = Duration.zero;
  Duration _sinceBeat = const Duration(days: 1);

  /// Niveau lisse 0..1 : monte vite, redescend doucement.
  double get level => _level;

  /// Mediums (voix, melodie) 0..1, lisse : allume un cercle autour de la
  /// pochette quand ils montent.
  double get midLevel => _midLevel;
  double _midLevel = 0;
  double _midFloor = 0;

  /// Ajoute une mesure ; [elapsed] = temps depuis la precedente. Renvoie la
  /// force du coup (0..1) si cette mesure en est un, sinon null.
  ///
  /// Peut etre appele a chaque image avec la meme mesure repetee (l'analyse
  /// en envoie une toutes les ~50 ms) : une valeur identique arrivee moins
  /// de 40 ms apres la precedente ne compte pas pour reperer les coups.
  double? add({
    required double bass,
    required double mid,
    double loudness = 1,
    required Duration elapsed,
  }) {
    final dt = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    _sinceBeat += elapsed;
    _sinceSample += elapsed;

    final b = bass.clamp(0.0, 1.0);
    final m = mid.clamp(0.0, 1.0);
    final loud = loudness.clamp(0.0, 1.0);
    final fresh = bass != _lastBass ||
        mid != _lastMid ||
        _sinceSample >= const Duration(milliseconds: 40);
    _lastBass = bass;
    _lastMid = mid;

    // Energie des basses en lineaire : c'est elle qui fait la luminosite,
    // pour qu'une basse qui tape fort se voie vraiment (l'echelle log
    // l'aplatissait).
    final lin = math.exp(b * _logScale) - 1;
    var isBeat = false;
    var rise = 0.0;
    if (fresh) {
      final sampleDt =
          _sinceSample.inMicroseconds / Duration.microsecondsPerSecond;
      _sinceSample = Duration.zero;
      final decay = math.pow(0.84, sampleDt).toDouble();
      _linPeak = math.max(lin, _linPeak * decay);
      _midPeak = math.max(m, _midPeak * decay);
      // Plus fort volume recent, qui redescend lentement (~moitie en une
      // minute) : l'intro calme d'un titre se compare encore au refrain
      // du precedent.
      // Volume lisse sur ~0,15 s : le pic au demarrage d'un titre (mesure
      // a 0,27 sur le telephone) ne doit pas bloquer les vagues ensuite.
      _loud += (loud - _loud) *
          (1 - math.pow(0.001, sampleDt).toDouble()).clamp(0.0, 1.0);
      _loudPeak = math.max(_loud, _loudPeak * math.pow(0.9885, sampleDt));

      // Coup = brusque montee de l'energie des basses (pas leur niveau)...
      rise = math.max(0.0, lin - _bassLin);
      _bassLin = lin;
      final midLin = math.exp(m * _logScale) - 1;
      final midRise = math.max(0.0, midLin - _midLin);
      _midLin = midLin;
      _midLinPeak = math.max(midLin, _midLinPeak * decay);
      // Plancher des mediums : suit tout de suite une baisse, remonte
      // lentement (~3 s). La voix ou la melodie qui arrive se mesure
      // au-dessus de ce plancher (les mediums bougent peu sur l'echelle
      // log : 0,55-0,70 sur le telephone).
      _midFloor = math.min(
          midLin,
          _midFloor +
              (midLin - _midFloor) *
                  (1 - math.pow(0.4, sampleDt).toDouble()).clamp(0.0, 1.0));
      isBeat = rise >= _linPeak * minBeatLevel &&
          rise > _riseAverage * beatRatio &&
          _sinceBeat >= minBeatGap &&
          // ... qui monte bien plus que les mediums : une note de piano
          // monte partout, une grosse caisse surtout dans le grave ...
          rise / math.max(_linPeak, 1) >
              1.5 * midRise / math.max(_midLinPeak, 1) &&
          // ... sur une vraie basse ...
          b >= minBeatBass &&
          // ... et seulement quand la musique est a son plus fort (pas sur
          // une intro au piano, gonflee par la normalisation d'Android).
          _loud >= 0.02 &&
          _loudPeak - _loud <= 0.067;
      // Moyenne des montees sur ~1 s.
      final a = 1 - math.pow(0.05, sampleDt).toDouble();
      _riseAverage += (rise - _riseAverage) * a.clamp(0.0, 1.0);
    }

    // Niveau : basses surtout, rapportees au pic recent (un morceau calme
    // bouge autant qu'un morceau fort), un peu de mediums.
    final bassNorm = (lin / math.max(_linPeak, 1)).clamp(0.0, 1.0);
    final midNorm = _midPeak <= 0.02 ? 0.0 : (m / _midPeak).clamp(0.0, 1.0);
    final target = (bassNorm * 0.8 + midNorm * 0.2) * _loudnessGate(_loud);
    // Attaque rapide, relachement doux : le visuel suit le coup sans
    // clignoter.
    final k = target > _level ? 0.6 : 1 - math.pow(0.05, dt).toDouble();
    _level += (target - _level) * k.clamp(0.0, 1.0);

    // Voix, melodie : mediums au-dessus de leur plancher recent.
    final span = _midLinPeak - _midFloor;
    final midTarget = span <= 1
        ? 0.0
        : ((_midLin - _midFloor) / span).clamp(0.0, 1.0) * _loudnessGate(_loud);
    final km = midTarget > _midLevel
        ? 1 - math.pow(0.002, dt).toDouble()
        : 1 - math.pow(0.1, dt).toDouble();
    _midLevel += (midTarget - _midLevel) * km.clamp(0.0, 1.0);

    if (!isBeat) return null;
    _sinceBeat = Duration.zero;
    return (rise / (_linPeak * 0.5)).clamp(0.0, 1.0);
  }

  /// 0..1 : eteint dans le silence, pres de 1 au plus fort recent, ~0,4
  /// sur un passage 6 dB plus doux. Le volume (0..1 pour -60..0 dB) mesure
  /// sur le telephone de Thibault : -51 dB sur l'intro piano de BREAKSH!T,
  /// -45 dB sur sa batterie, jamais au-dessus de -44 dB.
  double _loudnessGate(double loud) {
    // Le volume mesure suit celui du telephone (-53 dB a 3/16 sur le
    // haut-parleur) : seul le silence eteint tout, le reste est relatif.
    final absolute = ((loud - 0.02) / 0.04).clamp(0.0, 1.0);
    final relative = (1 - (_loudPeak - loud - 0.03) / 0.12).clamp(0.0, 1.0);
    return math.min(absolute, relative);
  }

  void reset() {
    _midPeak = 0.05;
    _level = 0;
    _midLevel = 0;
    _midFloor = 0;
    _lastBass = -1;
    _lastMid = -1;
    _bassLin = 0;
    _linPeak = 1;
    _riseAverage = 0;
    _midLin = 0;
    _midLinPeak = 1;
    _loudPeak = 0;
    _loud = 0;
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
