import '../services/subsonic_refs.dart';

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
  // Meme principe que Album : jamais d'URL avec jeton en memoire durable.
  final String? _coverRef;
  String? get coverPath => SubsonicRefs.resolve(_coverRef);
  final DateTime playedAt;

  RecentPlay({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.playedAt,
    String? coverPath,
  }) : _coverRef = SubsonicRefs.toStorable(coverPath);

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'coverPath': _coverRef,
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
