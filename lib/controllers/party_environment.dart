import '../services/party/party_models.dart';

/// Ce que les ecrans du mode Soiree lisent de l'app hors de la soiree
/// elle-meme (adresse du relais, compte, lecteur). Fourni par AppState ;
/// les tests de widgets en donnent un faux sans NAS ni moteur audio.
class PartyEnvironment {
  const PartyEnvironment({
    required this.relayUrl,
    required this.hostAuth,
    required this.userName,
    required this.playNow,
  });

  /// Adresse du relais deduite du serveur Navidrome, null sans serveur.
  final String? Function() relayUrl;

  /// Parametres Subsonic pour lancer une soiree (null : pas connecte).
  final Map<String, String>? Function() hostAuth;
  final String? Function() userName;

  /// Hote : lance tout de suite un titre de la file sur son lecteur.
  final Future<void> Function(PartyQueueItem item) playNow;
}
