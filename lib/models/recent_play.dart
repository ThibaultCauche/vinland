enum RecentPlayType { album, playlist, artist, friend }

/// Id virtuel utilise pour representer la collection "Titres likes" en tant
/// que playlist dans la section "Recemment ecoute" (elle n'a pas d'id reel).
const kLikedSongsRecentId = '__liked__';

/// Represente un "conteneur" (album, playlist ou artiste) recemment ecoute,
/// pour l'affichage type Spotify de la section "Recemment ecoute" de l'accueil.
class RecentPlay {
  final RecentPlayType type;
  final String id;
  final String title;
  final String subtitle;
  final String? coverPath;
  final DateTime playedAt;

  const RecentPlay({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.playedAt,
    this.coverPath,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'coverPath': coverPath,
        'playedAt': playedAt.toIso8601String(),
      };

  factory RecentPlay.fromJson(Map<String, dynamic> json) => RecentPlay(
        type: RecentPlayType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => RecentPlayType.album,
        ),
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        coverPath: json['coverPath'] as String?,
        playedAt: DateTime.tryParse(json['playedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
