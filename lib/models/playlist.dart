class Playlist {
  final String id;
  final String name;
  final List<String> trackIds;
  final DateTime createdAt;
  bool isSaved;

  /// Id de la playlist sur le serveur Navidrome. Null tant qu'elle n'a pas
  /// encore ete synchronisee (creee uniquement en local).
  String? serverId;

  /// Visible par les autres utilisateurs du serveur (donc par les "amis").
  bool isPublic;

  /// Nom d'utilisateur Navidrome du proprietaire. Null = playlist de
  /// l'utilisateur courant ; non-null = playlist d'un ami consultee en
  /// lecture seule (voir FriendsService/FriendProfile).
  final String? ownerUsername;

  /// Vrai pour la playlist auto-generee qui miroite les titres likes de son
  /// proprietaire (voir MusicService._syncLikesMirror) : reperee cote serveur
  /// via son champ "comment", pas par son nom (modifiable par l'utilisateur).
  final bool isLikesMirror;

  Playlist({
    required this.id,
    required this.name,
    List<String>? trackIds,
    DateTime? createdAt,
    this.isSaved = false,
    this.serverId,
    this.isPublic = false,
    this.ownerUsername,
    this.isLikesMirror = false,
  })  : trackIds = trackIds ?? [],
        createdAt = createdAt ?? DateTime.now();

  bool get isOwnedByCurrentUser => ownerUsername == null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdAt': createdAt.toIso8601String(),
        'isSaved': isSaved,
        'serverId': serverId,
        'isPublic': isPublic,
        'isLikesMirror': isLikesMirror,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) {
    DateTime? createdAt;
    try {
      createdAt = DateTime.parse(json['createdAt']);
    } catch (_) {
      createdAt = DateTime.now();
    }
    return Playlist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Inconnu',
      trackIds: List<String>.from(json['trackIds'] ?? []),
      createdAt: createdAt,
      isSaved: json['isSaved'] == true,
      serverId: json['serverId']?.toString(),
      isPublic: json['isPublic'] == true,
      isLikesMirror: json['isLikesMirror'] == true,
    );
  }
}
