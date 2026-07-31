class Album {
  final String id;
  final String title;
  final String artist;
  final List<String> trackIds;
  bool isSaved;
  final String? coverPath;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.trackIds,
    this.isSaved = false,
    this.coverPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'trackIds': trackIds,
        'isSaved': isSaved,
        'coverPath': coverPath,
      };

  factory Album.fromJson(Map<String, dynamic> json) => Album(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Inconnu',
        artist: json['artist']?.toString() ?? 'Inconnu',
        trackIds: List<String>.from(json['trackIds'] ?? []),
        isSaved: json['isSaved'] == true,
        coverPath: json['coverPath']?.toString(),
      );
}
