class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? filePath;
  bool isLiked;
  int playCount;
  DateTime? lastPlayed;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.filePath,
    this.isLiked = false,
    this.playCount = 0,
    this.lastPlayed,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration.inSeconds,
        'filePath': filePath,
        'isLiked': isLiked,
        'playCount': playCount,
        'lastPlayed': lastPlayed?.toIso8601String(),
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'],
        title: json['title'],
        artist: json['artist'],
        album: json['album'],
        duration: Duration(seconds: json['duration']),
        filePath: json['filePath'],
        isLiked: json['isLiked'] ?? false,
        playCount: json['playCount'] ?? 0,
        lastPlayed: json['lastPlayed'] != null
            ? DateTime.parse(json['lastPlayed'])
            : null,
      );
}
