import '../services/subsonic_refs.dart';

class Album {
  final String id;
  final String title;
  final String artist;
  final List<String> trackIds;
  bool isSaved;
  // Reference sans jeton pour une pochette Navidrome (voir SubsonicRefs),
  // chemin local sinon ; coverPath rend l'URL de la session en cours.
  final String? _coverRef;
  String? get coverPath => SubsonicRefs.resolve(_coverRef);
  final int? year;
  final DateTime? addedToServerAt;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.trackIds,
    this.isSaved = false,
    String? coverPath,
    this.year,
    this.addedToServerAt,
  }) : _coverRef = SubsonicRefs.toStorable(coverPath);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'trackIds': trackIds,
        'isSaved': isSaved,
        'coverPath': _coverRef,
        'year': year,
        'addedToServerAt': addedToServerAt?.toIso8601String(),
      };

  factory Album.fromJson(Map<String, dynamic> json) => Album(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Inconnu',
        artist: json['artist']?.toString() ?? 'Inconnu',
        trackIds: List<String>.from(json['trackIds'] ?? []),
        isSaved: json['isSaved'] == true,
        coverPath: json['coverPath']?.toString(),
        year: (json['year'] as num?)?.toInt(),
        addedToServerAt: json['addedToServerAt'] != null
            ? DateTime.tryParse(json['addedToServerAt'].toString())
            : null,
      );
}
