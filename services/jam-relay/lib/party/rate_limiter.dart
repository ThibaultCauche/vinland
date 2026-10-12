// Seau a jetons : `capacity` actions d'affilee, puis `perSecond` par
// seconde. Sert aux limites de debit de la soiree (voir
// docs/soiree-protocole.md, « Securite »). L'horloge est injectee pour que
// les tests n'aient pas a attendre.
class TokenBucket {
  final double capacity;
  final double perSecond;
  final DateTime Function() _now;
  double _tokens;
  DateTime _last;

  TokenBucket({
    required num capacity,
    required num perSecond,
    required DateTime Function() now,
  })  : capacity = capacity.toDouble(),
        perSecond = perSecond.toDouble(),
        _now = now,
        _tokens = capacity.toDouble(),
        _last = now();

  /// Consomme un jeton si possible ; false = trop rapide, refuser l'action.
  bool tryTake() {
    _refill();
    if (_tokens < 1) return false;
    _tokens -= 1;
    return true;
  }

  /// Vrai s'il reste au moins un jeton, sans en consommer.
  bool get hasToken {
    _refill();
    return _tokens >= 1;
  }

  void _refill() {
    final now = _now();
    final elapsed = now.difference(_last).inMicroseconds / 1e6;
    _last = now;
    if (elapsed > 0) {
      _tokens = (_tokens + elapsed * perSecond).clamp(0, capacity).toDouble();
    }
  }
}
