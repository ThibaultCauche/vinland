/// References Subsonic SANS jeton, a la place des URL completes.
///
/// Une URL Subsonic de stream ou de pochette contient le jeton
/// d'authentification (`t=md5(mdp + sel)`, `s=sel`, `u=utilisateur`) : la
/// stocker dans un Track, un Album, l'historique de recherche ou les
/// preferences revient a ecrire un equivalent du mot de passe en clair dans
/// des fichiers JSON (souvent synchronises OneDrive sous Windows). On ne
/// garde donc partout qu'une reference courte (`subsonic-cover:<id>`,
/// `subsonic-stream:<id>`), et l'URL reelle est reconstruite a la demande
/// par NavidromeService avec le jeton de la session en cours (voir
/// [resolve]). Bonus : le sel peut changer a chaque demarrage sans rien
/// casser, puisque plus rien de persiste n'en depend.
///
/// Volontairement sans dependance a NavidromeService (et donc aux fichiers
/// de config secrets) : les modeles importent ce fichier, et le service
/// branche ses constructeurs d'URL dans [streamUrlBuilder]/[coverUrlBuilder]
/// a sa creation.
class SubsonicRefs {
  SubsonicRefs._();

  static const coverPrefix = 'subsonic-cover:';
  static const streamPrefix = 'subsonic-stream:';

  /// Branches par NavidromeService : id Subsonic -> URL complete courante
  /// (chaine vide tant qu'aucun identifiant n'est charge).
  static String Function(String id)? streamUrlBuilder;
  static String Function(String id)? coverUrlBuilder;

  static String cover(String id) => '$coverPrefix$id';
  static String stream(String id) => '$streamPrefix$id';

  static bool isRef(String? value) =>
      value != null &&
      (value.startsWith(coverPrefix) || value.startsWith(streamPrefix));

  /// Id de pochette porte par une reference ou par une ancienne URL
  /// getCoverArt.view (cache d'avant la 1.3), sinon null.
  static String? coverIdOf(String? value) {
    if (value == null) return null;
    if (value.startsWith(coverPrefix)) {
      return value.substring(coverPrefix.length);
    }
    return _legacyId(value, 'getCoverArt');
  }

  /// Id de titre porte par une reference ou une ancienne URL stream.view.
  static String? streamIdOf(String? value) {
    if (value == null) return null;
    if (value.startsWith(streamPrefix)) {
      return value.substring(streamPrefix.length);
    }
    return _legacyId(value, 'stream');
  }

  /// Forme a stocker : une ancienne URL Subsonic (avec jeton) devient une
  /// reference, tout le reste (reference, chemin local, URL externe comme
  /// une pochette Deezer) est garde tel quel. Sert aussi de migration des
  /// caches ecrits avant la 1.3, qui contenaient des URL completes.
  static String? toStorable(String? value) {
    if (value == null) return null;
    final coverId = _legacyId(value, 'getCoverArt');
    if (coverId != null) return cover(coverId);
    final streamId = _legacyId(value, 'stream');
    if (streamId != null) return stream(streamId);
    return value;
  }

  /// Forme a utiliser (affichage, lecture) : une reference devient l'URL
  /// complete de la session en cours ; tout le reste est rendu tel quel.
  static String? resolve(String? value) {
    if (value == null) return null;
    if (value.startsWith(coverPrefix)) {
      return coverUrlBuilder?.call(value.substring(coverPrefix.length)) ?? '';
    }
    if (value.startsWith(streamPrefix)) {
      return streamUrlBuilder?.call(value.substring(streamPrefix.length)) ?? '';
    }
    return value;
  }

  /// Reconnait `.../rest/<endpoint>.view?...id=...` (forme ecrite par
  /// NavidromeService jusqu'a la 1.2.x) et en extrait l'id.
  static String? _legacyId(String value, String endpoint) {
    if (!value.startsWith('http')) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (last != '$endpoint.view' && last != endpoint) return null;
    if (!uri.pathSegments.contains('rest')) return null;
    final id = uri.queryParameters['id'];
    return (id == null || id.isEmpty) ? null : id;
  }
}
