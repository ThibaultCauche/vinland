class DiscoveredAlbum {
  final int id;
  final String title;
  final String artistName;
  final int? artistId;
  final String? coverUrl;
  final String? coverBigUrl;
  final int? nbTracks;
  final String? releaseDate;
  final String? genre;
  bool isInLibrary;

  DiscoveredAlbum({
    required this.id,
    required this.title,
    required this.artistName,
    this.artistId,
    this.coverUrl,
    this.coverBigUrl,
    this.nbTracks,
    this.releaseDate,
    this.genre,
    this.isInLibrary = false,
  });

  factory DiscoveredAlbum.fromJson(Map<String, dynamic> json) {
    final artist = json['artist'];
    return DiscoveredAlbum(
      id: json['id'] as int,
      title: json['title']?.toString() ?? 'Inconnu',
      artistName: artist is Map
          ? (artist['name']?.toString() ?? 'Inconnu')
          : (artist?.toString() ?? 'Inconnu'),
      artistId: artist is Map ? artist['id'] as int? : null,
      coverUrl: json['cover']?.toString(),
      coverBigUrl: json['cover_big']?.toString(),
      nbTracks: json['nb_tracks'] as int?,
      releaseDate: json['release_date']?.toString(),
      genre: json['genre_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': {'name': artistName, 'id': artistId},
        'cover': coverUrl,
        'cover_big': coverBigUrl,
        'nb_tracks': nbTracks,
        'release_date': releaseDate,
      };
}
