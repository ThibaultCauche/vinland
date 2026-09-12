/// Vue fusionnee d'une playlist collaborative : une sous-liste par
/// participant (une playlist Navidrome par personne, cf. MusicService.
/// fetchCollabPlaylist), dedupliquee et annotee de qui a ajoute quoi.
class CollabPlaylistView {
  final String groupId;
  final String name;
  final List<String> trackIds;

  /// trackId -> nom d'utilisateur Navidrome de la personne qui l'a ajoute.
  final Map<String, String> addedBy;

  const CollabPlaylistView({
    required this.groupId,
    required this.name,
    required this.trackIds,
    required this.addedBy,
  });
}
