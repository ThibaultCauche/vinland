class Album {
  final String id;
  final String title;
  final String artist;
  final List<String> trackIds;
  final bool isSaved;
  final String? coverPath; // ← chemin fichier

  Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.trackIds,
    this.isSaved = false,
    this.coverPath,
  });

  int get trackCount => trackIds.length;
}
