import 'dart:convert';

class Track {
  final String id;
  String title;
  String artist;
  String album;
  Duration duration;
  String? filePath;
  String? coverPath;
  bool isLiked;
  int playCount;
  DateTime? lastPlayed;
  DateTime? dateAdded;

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
    this.dateAdded,
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
        'dateAdded': dateAdded?.toIso8601String(),
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'],
        title: json['title'],
        artist: json['artist'],
        album: json['album'],
        duration: Duration(milliseconds: json['duration']),
        filePath: json['filePath'],
        coverPath: json['coverPath'],
        isLiked: json['isLiked'] ?? false,
        playCount: json['playCount'] ?? 0,
        lastPlayed: json['lastPlayed'] != null
            ? DateTime.parse(json['lastPlayed'])
            : null,
        dateAdded: json['dateAdded'] != null
            ? DateTime.parse(json['dateAdded'])
            : null,
      );
}
