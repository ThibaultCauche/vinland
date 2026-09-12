import 'dart:io';
import 'package:flutter/material.dart';

/// Fournit une cover (fichier local ou URL) decodee directement a la taille
/// d'affichage demandee plutot qu'a la resolution native du fichier puis
/// reduite au rendu. Decoder en pleine resolution des covers souvent bien
/// plus grandes que leur taille affichee est le principal cout de
/// rasterisation pendant un defilement rapide -- mesure sur la home desktop
/// (flutter drive --profile + integration_test/scroll_perf_test.dart) :
/// ~66ms/frame de raster en moyenne (164ms sur les pires frames, budget de
/// 16.6ms pour 60fps), 81 frames ayant depasse leur budget sur 5 flings,
/// alors que le temps de build restait excellent (1.5ms) -- la ou une image
/// deja a la bonne taille en memoire ne coute presque rien a rasteriser.
/// Le meme cout existe sur mobile (voir integration_test/mobile_scroll_perf_test.dart),
/// d'ou le partage de ce helper entre les vues desktop et mobile.
///
/// `width`/`height` sont les dimensions logiques d'AFFICHAGE de la cover ;
/// ResizeImage convertit en pixels physiques via le devicePixelRatio et
/// s'intercale entre le cache d'images de Flutter et le decodeur, donc le
/// resultat marche aussi bien avec un [Image] qu'avec un [DecorationImage]
/// (qui n'a pas de parametres cacheWidth/cacheHeight propres).
ImageProvider coverImageProvider(
  BuildContext context, {
  required String path,
  required double width,
  required double height,
}) {
  final double dpr = MediaQuery.devicePixelRatioOf(context);
  final ImageProvider base = path.startsWith('http')
      ? NetworkImage(path) as ImageProvider
      : FileImage(File(path));
  return ResizeImage(
    base,
    width: (width * dpr).round().clamp(1, 1 << 20),
    height: (height * dpr).round().clamp(1, 1 << 20),
    // policy: fit (pas exact, le defaut) -- une cover est presque toujours
    // carree alors que width/height demandes ne le sont pas forcement (ex:
    // le bandeau desktop DesktopHeroCard, tres large et bas) : "exact"
    // deformerait l'image en la reechantillonnant a ce rectangle avant meme
    // le BoxFit.cover applique a l'affichage. "fit" redimensionne en
    // respectant le ratio d'origine (le widget affichant l'image se charge
    // ensuite de recadrer via son propre BoxFit), donc jamais d'etirement.
    policy: ResizeImagePolicy.fit,
  );
}
