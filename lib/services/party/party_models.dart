// Donnees du mode Soiree telles que le relais les envoie (voir
// docs/soiree-protocole.md). Lecture tolerante : un champ manquant ou d'un
// type inattendu prend une valeur neutre plutot que de faire planter
// l'ecran, puisqu'un relais plus recent peut ajouter des champs.

/// Version majeure du protocole parlee par l'app (champ `v`).
const partyProtocolVersion = 1;

String _str(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

int _int(Object? value, [int fallback = 0]) => value is int ? value : fallback;

bool _bool(Object? value, [bool fallback = false]) =>
    value is bool ? value : fallback;

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
    : const [];

enum PartyRole { host, guest }

/// Un titre du catalogue (resultat de recherche ou titre en cours).
class PartySong {
  final String songId;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String? coverId;

  const PartySong({
    required this.songId,
    required this.title,
    this.artist = '',
    this.album = '',
    this.durationMs = 0,
    this.coverId,
  });

  /// `search_results` nomme l'id `id`, `now_playing` le nomme `songId`.
  factory PartySong.fromJson(Map<String, dynamic> json) => PartySong(
        songId: _str(json['songId'] ?? json['id']),
        title: _str(json['title'], '?'),
        artist: _str(json['artist']),
        album: _str(json['album']),
        durationMs: _int(json['durationMs']),
        coverId: json['coverId'] is String ? json['coverId'] as String : null,
      );

  /// Champs envoyes avec `suggest`/`now_playing` hors file : le relais s'en
  /// sert seulement s'il n'a pas de catalogue (sinon il relit la fiche).
  Map<String, dynamic> toJson() => {
        'songId': songId,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
        if (coverId != null) 'coverId': coverId,
      };
}

/// Une proposition dans la file, dans l'ordre de passage.
class PartyQueueItem {
  final String id;
  final PartySong song;
  final String by;
  final String byId;
  final int score;
  final int myVote;
  final bool mine;

  const PartyQueueItem({
    required this.id,
    required this.song,
    required this.by,
    required this.byId,
    this.score = 0,
    this.myVote = 0,
    this.mine = false,
  });

  factory PartyQueueItem.fromJson(Map<String, dynamic> json) => PartyQueueItem(
        id: _str(json['id']),
        song: PartySong.fromJson(json),
        by: _str(json['by'], '?'),
        byId: _str(json['byId']),
        score: _int(json['score']),
        myVote: _int(json['myVote']),
        mine: _bool(json['mine']),
      );
}

/// Un membre de la soiree, vu seulement par l'hote.
class PartyGuest {
  final String id;
  final String name;
  final bool online;
  final int pending;

  const PartyGuest({
    required this.id,
    required this.name,
    this.online = false,
    this.pending = 0,
  });

  factory PartyGuest.fromJson(Map<String, dynamic> json) => PartyGuest(
        id: _str(json['id']),
        name: _str(json['name'], '?'),
        online: _bool(json['online']),
        pending: _int(json['pending']),
      );
}

/// Regles choisies par l'hote au lancement (bornes dans le relais).
class PartyRules {
  final int maxPendingPerGuest;
  final int maxGuests;
  final bool votesEnabled;

  const PartyRules({
    this.maxPendingPerGuest = 3,
    this.maxGuests = 50,
    this.votesEnabled = true,
  });

  factory PartyRules.fromJson(Object? json) {
    if (json is! Map) return const PartyRules();
    return PartyRules(
      maxPendingPerGuest: _int(json['maxPendingPerGuest'], 3),
      maxGuests: _int(json['maxGuests'], 50),
      // Relais de la session 16 : pas de champ, les votes y sont toujours
      // possibles.
      votesEnabled: _bool(json['votesEnabled'], true),
    );
  }

  Map<String, dynamic> toJson() => {
        'maxPendingPerGuest': maxPendingPerGuest,
        'maxGuests': maxGuests,
        'votesEnabled': votesEnabled,
      };
}

/// Contenu d'un `queue_state`.
class PartyQueueState {
  final List<PartyQueueItem> items;
  final int guestCount;
  final bool hostOnline;

  /// Vide pour un invite (le relais n'envoie la liste qu'a l'hote).
  final List<PartyGuest> members;

  const PartyQueueState({
    this.items = const [],
    this.guestCount = 0,
    this.hostOnline = true,
    this.members = const [],
  });

  factory PartyQueueState.fromJson(Map<String, dynamic> json) =>
      PartyQueueState(
        items: _maps(json['items']).map(PartyQueueItem.fromJson).toList(),
        guestCount: _int(json['guestCount']),
        hostOnline: _bool(json['hostOnline'], true),
        members: _maps(json['members']).map(PartyGuest.fromJson).toList(),
      );
}

/// Phrase a montrer pour un code d'erreur du relais. Les textes du relais
/// sont techniques et sans accents : on garde les notres.
String partyErrorMessage(String code) => switch (code) {
      'version' => 'Le relais est trop ancien pour cette version de Vinland.',
      'unauthorized' =>
        'Le serveur a refusé ton compte pour lancer une soirée.',
      'bad_code' => 'Code inconnu. Vérifie les 6 caractères.',
      'bad_token' => 'Ta place dans la soirée a expiré, rentre à nouveau.',
      'expired' => 'La soirée est terminée.',
      'banned' => "L'hôte t'a exclu de la soirée.",
      'full' => 'La soirée est complète.',
      'forbidden' => "Action impossible (réservée à l'hôte ou désactivée).",
      'not_in_party' => "Tu n'es plus dans la soirée.",
      'limit' => 'Tu as déjà le maximum de titres en attente.',
      'duplicate' => 'Ce titre est déjà dans la file ou vient de passer.',
      'not_found' => "Ce titre n'est plus dans la file.",
      'invalid' => 'Demande refusée par le relais.',
      'rate_limited' => 'Doucement, réessaie dans quelques secondes.',
      'search_unavailable' =>
        "La recherche n'est pas disponible sur ce relais.",
      _ => 'Erreur du relais ($code).',
    };

/// Un titre passe pendant la soiree, pour le recap.
class PartyPlayed {
  final PartySong song;

  /// Pseudo de qui l'a propose, « Radio » pour la radio automatique, vide
  /// pour un titre lance par l'hote lui-meme.
  final String by;
  final DateTime at;

  const PartyPlayed({required this.song, required this.by, required this.at});

  Map<String, dynamic> toJson() => {
        ...song.toJson(),
        'by': by,
        'at': at.millisecondsSinceEpoch,
      };

  static PartyPlayed? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = json.cast<String, dynamic>();
    final song = PartySong.fromJson(map);
    if (song.songId.isEmpty) return null;
    return PartyPlayed(
      song: song,
      by: _str(map['by']),
      at: DateTime.fromMillisecondsSinceEpoch(_int(map['at'])),
    );
  }
}

/// Nom de la playlist du recap : « Soirée du 12/10 ». Une soiree commencee
/// apres minuit (avant 6 h) compte pour la veille, comme on la raconte.
String partyRecapName(DateTime start) {
  final day = start.hour < 6 ? start.subtract(const Duration(hours: 6)) : start;
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Soirée du ${two(day.day)}/${two(day.month)}';
}

/// Qui a propose combien de titres, du plus au moins actif :
/// « Proposé par : Léa (4), Max (2), l'hôte (3), la radio (1) ».
/// Sert de description a la playlist du recap.
String partyRecapComment(List<PartyPlayed> played) {
  final counts = <String, int>{};
  var host = 0, radio = 0;
  for (final p in played) {
    if (p.by.isEmpty) {
      host++;
    } else if (p.by == 'Radio') {
      radio++;
    } else {
      counts[p.by] = (counts[p.by] ?? 0) + 1;
    }
  }
  final guests = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final parts = [
    for (final e in guests) '${e.key} (${e.value})',
    if (host > 0) "l'hôte ($host)",
    if (radio > 0) 'la radio ($radio)',
  ];
  return parts.isEmpty ? '' : 'Proposé par : ${parts.join(', ')}';
}

/// Le bilan de la soiree, en quelques lignes : combien de temps elle a
/// dure, le DJ de la soiree (l'invite qui a fait passer le plus de titres),
/// l'artiste le plus joue. Rien a dire pour une soiree vide.
List<String> partyRecapHighlights(List<PartyPlayed> played) {
  if (played.isEmpty) return const [];
  final lines = <String>[];

  final times = played.map((p) => p.at).toList()..sort();
  final span = times.last.difference(times.first);
  if (span >= const Duration(minutes: 30)) {
    final h = span.inHours, m = span.inMinutes % 60;
    lines.add(
        'Durée : ${h > 0 ? '$h h ${m.toString().padLeft(2, '0')}' : '$m min'}');
  }

  final byGuest = <String, int>{};
  final byArtist = <String, int>{};
  for (final p in played) {
    if (p.by.isNotEmpty && p.by != 'Radio') {
      byGuest.update(p.by, (n) => n + 1, ifAbsent: () => 1);
    }
    final artist = p.song.artist.trim();
    if (artist.isNotEmpty) {
      byArtist.update(artist, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  final dj = _leader(byGuest);
  if (dj != null && dj.$2 >= 2) {
    lines.add('DJ de la soirée : ${dj.$1} (${dj.$2} titres)');
  }
  final artist = _leader(byArtist);
  if (artist != null && artist.$2 >= 2) {
    lines.add('Artiste le plus joué : ${artist.$1} (${artist.$2} fois)');
  }
  return lines;
}

/// Le plus grand compteur ; un ex aequo n'a pas de gagnant.
(String, int)? _leader(Map<String, int> counts) {
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (sorted.isEmpty) return null;
  if (sorted.length > 1 && sorted[1].value == sorted[0].value) return null;
  return (sorted.first.key, sorted.first.value);
}
