enum PinnedItemType { album, playlist, artist }

/// Un album/playlist/artiste epingle par l'utilisateur pour rester toujours
/// visible dans les tuiles de l'accueil, meme s'il n'a pas ete ecoute
/// recemment. Contrairement a RecentPlay, ne stocke pas de coverPath : cette
/// liste est synchronisee entre appareils/plateformes (voir
/// MusicService._syncPinnedMirror) via le profil Navidrome, et un chemin de
/// fichier local n'aurait aucun sens sur un autre appareil -- chaque cote
/// resout sa propre cover localement a partir de type+id. "Titres likes" se
/// represente en type playlist avec kLikedSongsRecentId (recent_play.dart)
/// comme id, meme convention que RecentPlay.
class PinnedItem {
  final PinnedItemType type;
  final String id;
  final String title;
  final String subtitle;

  const PinnedItem({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
  });

  bool sameTarget(PinnedItemType type, String id) =>
      this.type == type && this.id == id;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'id': id,
        'title': title,
        'subtitle': subtitle,
      };

  factory PinnedItem.fromJson(Map<String, dynamic> json) => PinnedItem(
        type: PinnedItemType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => PinnedItemType.album,
        ),
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
      );
}
