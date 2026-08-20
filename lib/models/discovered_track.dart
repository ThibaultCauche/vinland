class DiscoveredTrack {
  final int id;
  final String title;
  final String artistName;
  final int? artistId;
  final String albumName;
  final int? albumId;
  final String? coverUrl;
  final Duration? duration;
  final int? trackPosition;
  final String? previewUrl;
  bool isInLibrary;

  DiscoveredTrack({
    required this.id,
    required this.title,
    required this.artistName,
    this.artistId,
    required this.albumName,
    this.albumId,
    this.coverUrl,
    this.duration,
    this.trackPosition,
    this.previewUrl,
    this.isInLibrary = false,
  });

  factory DiscoveredTrack.fromJson(Map<String, dynamic> json) {
    final artist = json['artist'];
    final album = json['album'];
    final durationSec = json['duration'] as int?;

    return DiscoveredTrack(
      id: json['id'] as int,
      title: json['title']?.toString() ?? 'Inconnu',
      artistName: artist is Map
          ? (artist['name']?.toString() ?? 'Inconnu')
          : (artist?.toString() ?? 'Inconnu'),
      artistId: artist is Map ? artist['id'] as int? : null,
      albumName: album is Map
          ? (album['title']?.toString() ?? 'Inconnu')
          : (album?.toString() ?? 'Inconnu'),
      albumId: album is Map ? album['id'] as int? : null,
      coverUrl: album is Map
          ? album['cover']?.toString()
          : json['album']?['cover']?.toString(),
      duration: durationSec != null ? Duration(seconds: durationSec) : null,
      trackPosition: json['track_position'] as int?,
      previewUrl: json['preview']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': {'name': artistName, 'id': artistId},
        'album': {'title': albumName, 'id': albumId, 'cover': coverUrl},
        'duration': duration?.inSeconds,
        'track_position': trackPosition,
        'preview': previewUrl,
      };
}
