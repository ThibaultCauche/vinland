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
