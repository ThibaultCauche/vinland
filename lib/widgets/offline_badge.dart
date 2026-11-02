import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/app_state.dart';

/// Etat hors-ligne d'un titre pour l'affichage d'une ligne : telecharge
/// (petite fleche verte), et jouable maintenant (sinon la ligne est grisee
/// en mode hors-ligne).
({bool downloaded, bool available}) watchTrackOffline(
    BuildContext context, Track track) {
  return context.select<AppState, ({bool downloaded, bool available})>(
    (s) => (
      downloaded: s.isTrackOffline(track.id),
      available: s.isTrackAvailable(track),
    ),
  );
}

/// Petite fleche verte « telecharge » devant le nom de l'artiste.
class OfflineBadge extends StatelessWidget {
  const OfflineBadge({super.key, this.size = 14});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: 'Disponible hors connexion',
        child: Icon(Icons.download_for_offline,
            color: const Color(0xFF1DB954), size: size),
      ),
    );
  }
}
