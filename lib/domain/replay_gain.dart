import 'dart:math' as math;

/// Gains ReplayGain d'un titre, tels que les renvoie Navidrome (champ
/// OpenSubsonic `replayGain` d'un titre, rempli depuis les tags du fichier :
/// beets, foobar...). Tout est en dB sauf les crêtes (amplitude, 1.0 = 0 dBFS).
class ReplayGain {
  final double? trackGain;
  final double? albumGain;
  final double? trackPeak;
  final double? albumPeak;

  /// Gain de base propre au format (R128 des Opus), a ajouter au reste.
  final double? baseGain;

  const ReplayGain({
    this.trackGain,
    this.albumGain,
    this.trackPeak,
    this.albumPeak,
    this.baseGain,
  });

  bool get isEmpty => trackGain == null && albumGain == null;

  /// Lit l'objet OpenSubsonic (`{"trackGain": -7.2, ...}`) ou notre propre
  /// cache (memes cles). Null si aucun gain exploitable.
  static ReplayGain? fromJson(Object? json) {
    if (json is! Map) return null;
    double? read(String key) {
      final v = json[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final rg = ReplayGain(
      trackGain: read('trackGain'),
      albumGain: read('albumGain'),
      trackPeak: read('trackPeak'),
      albumPeak: read('albumPeak'),
      baseGain: read('baseGain'),
    );
    return rg.isEmpty ? null : rg;
  }

  Map<String, dynamic> toJson() => {
        if (trackGain != null) 'trackGain': trackGain,
        if (albumGain != null) 'albumGain': albumGain,
        if (trackPeak != null) 'trackPeak': trackPeak,
        if (albumPeak != null) 'albumPeak': albumPeak,
        if (baseGain != null) 'baseGain': baseGain,
      };
}

enum ReplayGainMode {
  /// Volume tel quel (comportement d'avant).
  off,

  /// Chaque titre ramene au meme niveau : le mieux pour une soiree en
  /// aleatoire, ou les titres viennent d'albums masterises tres differemment.
  track,

  /// Garde les ecarts voulus entre titres d'un meme album (intro calme,
  /// morceau fort) : le mieux pour ecouter un album en entier.
  album,
}

/// Volume (0..1) a appliquer au moteur pour un titre.
///
/// Les moteurs ne savent pas amplifier au-dela de 1 sans saturer (just_audio
/// plafonne a 1 sur Android) : un titre plus calme que la reference reste
/// donc a 1, seuls les titres trop forts sont baisses -- c'est le cas de la
/// plupart des masters recents, qui sont justement ceux qui « sautent » au
/// milieu d'une playlist. Un titre sans tags ReplayGain n'est pas touche.
double replayGainVolume(
  ReplayGain? gain,
  ReplayGainMode mode, {
  double preampDb = 0,
}) {
  if (mode == ReplayGainMode.off || gain == null) return 1.0;
  final db = mode == ReplayGainMode.album
      ? (gain.albumGain ?? gain.trackGain)
      : (gain.trackGain ?? gain.albumGain);
  if (db == null) return 1.0;
  var linear =
      math.pow(10, (db + (gain.baseGain ?? 0) + preampDb) / 20).toDouble();
  // Crete connue : ne jamais pousser le signal au-dela de 0 dBFS.
  final peak = mode == ReplayGainMode.album
      ? (gain.albumPeak ?? gain.trackPeak)
      : (gain.trackPeak ?? gain.albumPeak);
  if (peak != null && peak > 0) linear = math.min(linear, 1 / peak);
  return linear.clamp(0.0, 1.0);
}
