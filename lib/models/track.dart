class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  // Pour un titre Navidrome, ces deux champs sont une URL absolue construite
  // avec l'URL du serveur au moment du sync (voir NavidromeService.
  // _mapSubsonicTrack) : pas 'final', pour que
  // MusicService.refreshNavidromeTrackUrls puisse les reconstruire si l'URL
  // du serveur change (VPN <-> Funnel...) sans attendre un resync complet.
  String? filePath;
  String? coverPath;
  bool isLiked;
  // Variante visuelle du like (coeur double), purement locale -- pas
  // d'equivalent cote Navidrome/Subsonic, contrairement a isLiked qui se
  // synchronise via star.view. Implique isLiked (voir MusicService.
  // toggleSuperLike) : un titre super-like est toujours aussi like.
  bool superLiked;
  int playCount;
  DateTime? lastPlayed;
  DateTime? dateAdded;
  final String? albumId;
  final String? albumArtist;
  final int? year;
  final DateTime? addedToServerAt;
  final String? genre;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.filePath,
    this.coverPath,
    this.isLiked = false,
    this.superLiked = false,
    this.playCount = 0,
    this.lastPlayed,
    this.dateAdded,
    this.albumId,
    this.albumArtist,
    this.year,
    this.addedToServerAt,
    this.genre,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration.inMilliseconds,
        'filePath': filePath,
        'coverPath': coverPath,
        'isLiked': isLiked,
        'superLiked': superLiked,
        'playCount': playCount,
        'lastPlayed': lastPlayed?.toIso8601String(),
        'dateAdded': dateAdded?.toIso8601String(),
        'albumId': albumId,
        'albumArtist': albumArtist,
        'year': year,
        'addedToServerAt': addedToServerAt?.toIso8601String(),
        'genre': genre,
      };

  factory Track.fromJson(Map<String, dynamic> json) {
    final rawDuration = json['duration'];
    int ms = 0;
    if (rawDuration is int) {
      ms = rawDuration;
    } else if (rawDuration is double) {
      ms = rawDuration.toInt();
    } else if (rawDuration is String) {
      ms = int.tryParse(rawDuration) ?? 0;
    }
    if (ms < 0) ms = 0;

    DateTime? parseDate(String? key) {
      if (key == null) return null;
      try {
        return DateTime.parse(json[key]);
      } catch (_) {
        return null;
      }
    }

    return Track(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Inconnu',
      artist: json['artist']?.toString() ?? 'Inconnu',
      album: json['album']?.toString() ?? 'Inconnu',
      duration: Duration(milliseconds: ms),
      filePath: json['filePath']?.toString(),
      coverPath: json['coverPath']?.toString(),
      isLiked: json['isLiked'] == true,
      superLiked: json['superLiked'] == true,
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      lastPlayed: parseDate('lastPlayed'),
      dateAdded: parseDate('dateAdded'),
      albumId: json['albumId']?.toString(),
      albumArtist: json['albumArtist']?.toString(),
      year: (json['year'] as num?)?.toInt(),
      addedToServerAt: json['addedToServerAt'] != null
          ? DateTime.tryParse(json['addedToServerAt'].toString())
          : null,
      genre: json['genre']?.toString(),
    );
  }
}
