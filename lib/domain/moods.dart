import '../models/track.dart';
import '../services/matching_service.dart';

/// Un mood de l'accueil, deduit du genre ecrit dans les tags des fichiers
/// (pas d'info « triste/joyeux » la-dedans : voir Last.fm pour ca plus tard).
class Mood {
  const Mood(this.label, this.keywords);
  final String label;

  /// Mots cherches dans le genre normalise (MatchingService.normalize :
  /// minuscules, sans accents ni ponctuation -- « Hip-Hop » -> « hip hop »).
  final List<String> keywords;
}

const moods = [
  Mood('Chill', [
    'chill',
    'lo fi',
    'lofi',
    'ambient',
    'downtempo',
    'acoustic',
    'jazz',
    'soul',
    'r b',
    'rnb',
    'bossa',
    'trip hop'
  ]),
  Mood('Rock', ['rock', 'metal', 'punk', 'grunge']),
  Mood('Rap', ['rap', 'hip hop', 'trap', 'drill']),
  Mood('Électro', [
    'electro',
    'edm',
    'house',
    'techno',
    'dubstep',
    'trance',
    'drum and bass',
    'dance'
  ]),
  Mood('Pop', ['pop', 'variete', 'chanson']),
  Mood('BO & classique', [
    'soundtrack',
    'score',
    'classical',
    'classique',
    'orchestral',
    'game',
    'film'
  ]),
];

/// Humeurs tirees des tags Last.fm (voir LastfmService) : libelle affiche,
/// tag Last.fm (en anglais, comme les utilisateurs de Last.fm les posent).
const lastfmMoods = [
  ('Triste', 'sad'),
  ('Joyeux', 'happy'),
  ('Mélancolique', 'melancholic'),
  ('Énervé', 'aggressive'),
  ('Motivé', 'energetic'),
  ('Romantique', 'romantic'),
  ('Planant', 'chillout'),
];

/// Titres de [library] dont le genre correspond a [mood].
List<Track> tracksForMood(Mood mood, List<Track> library) => [
      for (final t in library)
        if (t.genre != null &&
            !t.isPlaceholder &&
            mood.keywords
                .any((k) => MatchingService.normalize(t.genre!).contains(k)))
          t
    ];
