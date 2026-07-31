class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? filePath;
  final String? coverPath;
  bool isLiked;
  int playCount;
  DateTime? lastPlayed;
  DateTime? dateAdded; // ← AJOUTÉ

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.filePath,
    this.coverPath,
    this.isLiked = false,
    this.playCount = 0,
    this.lastPlayed,
    this.dateAdded, // ← AJOUTÉ
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
        'playCount': playCount,
        'lastPlayed': lastPlayed?.toIso8601String(),
        'dateAdded': dateAdded?.toIso8601String(), // ← AJOUTÉ
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
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      lastPlayed: parseDate('lastPlayed'),
      dateAdded: parseDate('dateAdded'),
    );
  }
}
