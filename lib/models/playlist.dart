class Playlist {
  final String id;
  final String name;
  final List<String> trackIds;
  final DateTime createdAt;
  bool isSaved;

  Playlist({
    required this.id,
    required this.name,
    List<String>? trackIds,
    DateTime? createdAt,
    this.isSaved = false,
  })  : trackIds = trackIds ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdAt': createdAt.toIso8601String(),
        'isSaved': isSaved,
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
    );
  }
}
