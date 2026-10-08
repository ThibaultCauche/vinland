import 'dart:ui';
import 'package:flutter/material.dart';

/// Hauteur totale a reserver en haut du CONTENU (pas du fond) d'un ecran qui
/// utilise `extendBodyBehindAppBar: true` -- l'AppBar reste affichee a sa
/// position normale, seul le fond (AppBackground/PlatformBackground) doit
/// s'etendre derriere elle pour eviter toute bande d'une autre couleur en
/// haut de l'ecran (retour utilisateur). = hauteur standard d'une AppBar
/// Material (kToolbarHeight) + l'inset de la barre de statut du device.
double appBarSafeTopPadding(BuildContext context) =>
    kToolbarHeight + MediaQuery.of(context).padding.top;

/// A placer dans `flexibleSpace` d'un AppBar transparente combinee a
/// `extendBodyBehindAppBar` : sans ca, le contenu qui defile en dessous
/// (ListView/CustomScrollView) devient visible PAR TRANSPARENCE a travers la
/// barre et remonte par-dessus le titre de la page, le rendant illisible
/// (retour utilisateur). Le flou garde le meme fond de page qu'avant
/// derriere la barre (juste ce qui defile devient illisible dessous), au
/// lieu d'un fond opaque qui aurait recree la "bande d'une autre couleur"
/// que extendBodyBehindAppBar visait justement a eviter.
class AppBarBlurBackground extends StatelessWidget {
  const AppBarBlurBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(color: Colors.black.withOpacity(0.15)),
      ),
    );
  }
}
