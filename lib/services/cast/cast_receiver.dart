import 'package:flutter/painting.dart';

import '../../domain/lyrics.dart';

/// Recepteur Chromecast de Vinland (dossier cast-receiver/ du depot) : ecran
/// tele avec la grille d'hexagones, la pochette et les paroles.
///
/// Null tant que le recepteur n'est pas enregistre dans la Google Cast SDK
/// Developer Console : l'app lance alors le recepteur par defaut de Google.
/// Si le lancement du recepteur Vinland echoue (Chromecast pas encore
/// autorisee pour un recepteur en test, page injoignable), l'app retombe
/// aussi sur celui de Google.
const String? kVinlandReceiverAppId = null;

/// Espace de noms des messages propres a Vinland (paroles, couleur).
const kVinlandCastNamespace = 'urn:x-cast:fr.vinland.cast';

/// Couleur d'accent de l'ecran tele, tiree de la pochette : teinte gardee,
/// assez vive et claire pour un fond sombre ; vert Vinland si elle est
/// terne ou inconnue.
String castAccentHex(Color? cover) {
  var color = const Color(0xFF1DB954);
  if (cover != null) {
    final hsl = HSLColor.fromColor(cover);
    if (hsl.saturation >= 0.15) {
      color = hsl
          .withSaturation(hsl.saturation < 0.55 ? 0.55 : hsl.saturation)
          .withLightness(0.58)
          .toColor();
    }
  }
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

/// Paroles au format du recepteur : `t` en millisecondes (null si les
/// paroles ne sont pas synchronisees).
List<Map<String, Object?>> castLyricLines(Lyrics? lyrics) {
  if (lyrics == null || lyrics.isEmpty) return const [];
  return [
    for (final line in lyrics.lines)
      {'t': line.start?.inMilliseconds, 'text': line.text},
  ];
}
