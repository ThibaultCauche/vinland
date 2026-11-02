/// Pochettes telechargees pour l'ecoute hors-ligne, retrouvees par leur id
/// de pochette Subsonic.
///
/// Volontairement statique et sans dependance (comme SubsonicRefs) : le
/// fournisseur d'images (rawCoverImageProvider) et le lecteur (pochette de
/// la notification) la consultent sans connaitre MusicService, qui y branche
/// [lookup] a sa creation.
class OfflineCovers {
  OfflineCovers._();

  /// Id de pochette -> chemin du fichier local, ou null s'il n'a pas ete
  /// telecharge.
  static String? Function(String coverId)? lookup;

  static String? pathFor(String? coverId) {
    if (coverId == null || coverId.isEmpty) return null;
    return lookup?.call(coverId);
  }
}
