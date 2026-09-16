import 'package:flutter/material.dart';

/// Hauteur totale a reserver en haut du CONTENU (pas du fond) d'un ecran qui
/// utilise `extendBodyBehindAppBar: true` -- l'AppBar reste affichee a sa
/// position normale, seul le fond (AppBackground/PlatformBackground) doit
/// s'etendre derriere elle pour eviter toute bande d'une autre couleur en
/// haut de l'ecran (retour utilisateur). = hauteur standard d'une AppBar
/// Material (kToolbarHeight) + l'inset de la barre de statut du device.
double appBarSafeTopPadding(BuildContext context) =>
    kToolbarHeight + MediaQuery.of(context).padding.top;
