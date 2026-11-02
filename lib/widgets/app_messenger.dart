import 'package:flutter/material.dart';

/// Messagerie de l'app entiere (branchee sur MaterialApp) : permet a la
/// logique sans BuildContext (AppState, lecteur) d'afficher un court
/// message en bas de l'ecran.
final GlobalKey<ScaffoldMessengerState> vinlandMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void showAppMessage(String text) {
  final messenger = vinlandMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
