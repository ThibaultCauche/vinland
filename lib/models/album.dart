class Album {
  final String id;
  final String title;
  final String artist;
  final List<String> trackIds;
  final Duration? duration;
  bool isSaved;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    this.trackIds = const [],
    this.duration,
    this.isSaved = false,
  });

  int get trackCount => trackIds.length;
}
