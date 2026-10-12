import 'package:flutter/widgets.dart';

import '../models/track.dart';
import '../services/party/party_models.dart';

/// Une playlist proposee pour le pack hors-ligne de la soiree.
typedef PartyPackPlaylist = ({String id, String name, List<Track> tracks});

/// Ce que les ecrans du mode Soiree lisent de l'app hors de la soiree
/// elle-meme (adresse du relais, compte, lecteur). Fourni par AppState ;
/// les tests de widgets en donnent un faux sans NAS ni moteur audio. Les
/// extras (radio, recap, pack hors-ligne) sont facultatifs : sans eux, leur
/// entree n'est simplement pas affichee.
class PartyEnvironment {
  const PartyEnvironment({
    required this.relayUrl,
    required this.hostAuth,
    required this.userName,
    required this.playNow,
    this.radioEnabled,
    this.setRadioEnabled,
    this.saveRecap,
    this.shareRecap,
    this.packPlaylists,
    this.isOffline,
    this.downloadOffline,
  });

  /// Adresse du relais deduite du serveur Navidrome, null sans serveur.
  final String? Function() relayUrl;

  /// Parametres Subsonic pour lancer une soiree (null : pas connecte).
  final Map<String, String>? Function() hostAuth;
  final String? Function() userName;

  /// Hote : lance tout de suite un titre de la file sur son lecteur.
  final Future<void> Function(PartyQueueItem item) playNow;

  /// Radio automatique quand la file est vide (voir PartyHostDj).
  final bool Function()? radioEnabled;
  final void Function(bool enabled)? setRadioEnabled;

  /// Cree la playlist du recap ([name], titres dans l'ordre de passage) et
  /// renvoie son id, ou null en cas d'echec.
  final Future<String?> Function(String name, List<PartyPlayed> played)?
      saveRecap;

  /// Partage la playlist [playlistId] (boite de reception des amis, ou lien).
  final Future<void> Function(BuildContext context, String playlistId)?
      shareRecap;

  /// Playlists de l'hote pour le pack hors-ligne.
  final List<PartyPackPlaylist> Function()? packPlaylists;
  final bool Function(List<Track> tracks)? isOffline;

  /// Telecharge [tracks] sur l'appareil ; [onProgress] de 0 a 1.
  final Future<void> Function(
          List<Track> tracks, void Function(double progress) onProgress)?
      downloadOffline;
}
