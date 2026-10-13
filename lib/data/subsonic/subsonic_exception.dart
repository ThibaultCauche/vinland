/// Erreur d'un appel Subsonic.
///
/// Subsonic repond HTTP 200 meme quand l'appel echoue (mauvais identifiants,
/// playlist inconnue, droits insuffisants...) : l'echec n'est visible que
/// dans `subsonic-response.status == "failed"`. Avant ce client, l'app ne
/// regardait que le code HTTP et croyait donc reussir des likes ou des
/// modifications de playlist refuses par le serveur.
class SubsonicException implements Exception {
  /// Code d'erreur Subsonic (10 = parametre manquant, 40 = identifiants
  /// invalides, 50 = non autorise, 70 = introuvable...), null quand
  /// l'erreur ne vient pas du protocole Subsonic lui-meme (HTTP, JSON).
  final int? code;
  final String message;

  /// Code HTTP quand le serveur n'a pas repondu 200.
  final int? httpStatus;

  const SubsonicException(this.message, {this.code, this.httpStatus});

  /// Identifiants refuses (codes Subsonic 40 et 41) : inutile de reessayer.
  bool get isAuthError => code == 40 || code == 41;

  @override
  String toString() {
    final details = [
      if (code != null) 'code $code',
      if (httpStatus != null) 'HTTP $httpStatus',
    ].join(', ');
    return details.isEmpty
        ? 'SubsonicException: $message'
        : 'SubsonicException ($details): $message';
  }
}

/// Le serveur n'a pas pu etre joint (coupure, timeout, handshake TLS rate
/// sur le tunnel Tailscale...). Seule erreur que le client reessaie : une
/// erreur Subsonic, elle, donnerait la meme reponse au deuxieme essai.
class SubsonicNetworkException extends SubsonicException {
  final Object cause;

  const SubsonicNetworkException(this.cause) : super('serveur injoignable');

  @override
  String toString() => 'SubsonicNetworkException: $cause';
}
