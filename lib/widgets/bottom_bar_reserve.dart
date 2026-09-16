import 'package:flutter/material.dart';

/// Hauteur totale occupee par la barre flottante du bas (mini-player +
/// navigation par onglets, voir main.dart) : le Scaffold principal utilise
/// extendBody: true, donc le contenu scrollable de chaque page passe EN
/// DESSOUS de cette barre au lieu d'etre automatiquement pousse au-dessus --
/// chaque page scrollable doit reserver cet espace elle-meme en bas de sa
/// liste, sinon ses derniers elements restent caches derriere (retour
/// utilisateur). Valeur = hauteur fixe du mini-player (64 + 8 de marge, voir
/// MiniPlayer) + hauteur standard Material d'une BottomNavigationBar (56) +
/// l'inset de zone de securite bas du device (barre de geste/home
/// indicator), qui varie d'un telephone a l'autre.
double bottomBarReserve(BuildContext context) =>
    MediaQuery.of(context).padding.bottom;
