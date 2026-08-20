class DiscoveredArtist {
  final int id;
  final String name;
  final String? pictureUrl;
  final String? pictureBigUrl;
  final int? nbAlbums;
  final int? nbFans;

  DiscoveredArtist({
    required this.id,
    required this.name,
    this.pictureUrl,
    this.pictureBigUrl,
    this.nbAlbums,
    this.nbFans,
  });

  factory DiscoveredArtist.fromJson(Map<String, dynamic> json) {
    return DiscoveredArtist(
      id: json['id'] as int,
      name: json['name']?.toString() ?? 'Inconnu',
      pictureUrl: json['picture']?.toString(),
      pictureBigUrl: json['picture_big']?.toString(),
      nbAlbums: json['nb_album'] as int?,
      nbFans: json['nb_fan'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'picture': pictureUrl,
        'picture_big': pictureBigUrl,
        'nb_album': nbAlbums,
        'nb_fan': nbFans,
      };
}
