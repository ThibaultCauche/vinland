class Playlist {
  final String id;
  final String name;
  final List<String> trackIds;
  final DateTime createdAt;
  bool isSaved;

  Playlist({
    required this.id,
    required this.name,
    this.trackIds = const [],
    DateTime? createdAt,
    this.isSaved = false,
  }) : createdAt = createdAt ?? DateTime.now();

  int get trackCount => trackIds.length;
}
