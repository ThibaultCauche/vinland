/// Choix de partage avec les amis (likes, écoutes récentes, titre en cours)
/// et le fait que l'utilisateur les ait explicitement validés.
///
/// Jusqu'à la 1.2.x, les trois partages étaient activés par défaut sans rien
/// demander : un nouvel utilisateur exposait ses likes et ce qu'il écoutait
/// à tout le serveur sans le savoir. Désormais un nouveau compte part de
/// « rien de partagé » et l'app demande au premier lancement (voir
/// SharingConsentGate). Un compte existant garde ses réglages actuels, mais
/// on lui montre la même question une fois, pré-remplie avec ce qu'il
/// partage déjà, pour qu'il le confirme en connaissance de cause plutôt que
/// de voir ses amis perdre son activité du jour au lendemain.
class SharingConsent {
  final bool likes;
  final bool recentPlays;
  final bool nowPlaying;

  /// true une fois que l'utilisateur a validé l'écran de consentement.
  final bool asked;

  const SharingConsent({
    required this.likes,
    required this.recentPlays,
    required this.nowPlaying,
    required this.asked,
  });

  /// Nouveau compte (aucun cache local) : rien n'est partagé tant que
  /// l'utilisateur n'a pas répondu.
  static const SharingConsent none = SharingConsent(
    likes: false,
    recentPlays: false,
    nowPlaying: false,
    asked: false,
  );

  /// Lit les choix depuis le cache de bibliothèque (library_*.json).
  /// Un cache écrit par une version <= 1.2.x n'a pas la clé
  /// `sharingConsentAsked` : ses partages valaient `true` par défaut, on les
  /// garde tels quels (voir le commentaire de la classe) mais `asked` reste
  /// false pour que la question soit posée.
  factory SharingConsent.fromCache(Map<String, dynamic>? data) {
    if (data == null) return none;
    return SharingConsent(
      likes: data['shareLikesWithFriends'] as bool? ?? true,
      recentPlays: data['shareRecentPlaysWithFriends'] as bool? ?? true,
      nowPlaying: data['shareNowPlayingWithFriends'] as bool? ?? true,
      asked: data['sharingConsentAsked'] as bool? ?? false,
    );
  }
}
