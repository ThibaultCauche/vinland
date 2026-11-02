import 'package:flutter/material.dart';

import '../models/track.dart';
import '../providers/app_state.dart';
import '../widgets/offline_actions.dart';
import 'desktop_hero_card.dart';

/// Entree « Télécharger » / « Supprimer le téléchargement » des menus « ... »
/// du PC (album, playlist, titres likes). L'etat est relu au clic : le
/// menu peut avoir ete construit avant la fin d'un telechargement.
DesktopHeroMenuAction desktopOfflineAction(
  BuildContext context,
  AppState state, {
  required List<Track> tracks,
  String? collection,
  String removeMessage = 'Ce contenu ne sera plus disponible hors connexion.',
}) {
  final downloaded =
      isDownloadedForOffline(state, tracks, collection: collection);
  return DesktopHeroMenuAction(
    label: downloaded ? 'Supprimer le téléchargement' : 'Télécharger',
    icon: downloaded ? Icons.download_done : Icons.download_outlined,
    destructive: downloaded,
    onTap: () {
      if (isDownloadedForOffline(state, tracks, collection: collection)) {
        removeOfflineDownload(context,
            tracks: tracks, collection: collection, message: removeMessage);
      } else {
        downloadForOffline(context, tracks: tracks, collection: collection);
      }
    },
  );
}
