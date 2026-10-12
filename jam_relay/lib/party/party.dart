// Etat d'une soiree et regles de la file (voir docs/soiree-protocole.md,
// « Regles de la file »). Logique pure, sans reseau : PartyHub s'occupe des
// connexions et appelle ces methodes.

/// Infos d'un titre telles que montrees aux invites. Jamais d'URL ni
/// d'identifiant Navidrome : seulement de quoi afficher et identifier.
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

  Map<String, dynamic> toJson() => {
        'songId': songId,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
        'coverId': coverId,
      };
}

class PartyRules {
  final int maxPendingPerGuest;
  final int maxGuests;
  final int recentHistory;

  /// Faux : personne ne vote, la file suit seulement l'ordre equitable
  /// (l'hote prefere parfois eviter les « -1 » entre amis).
  final bool votesEnabled;

  const PartyRules({
    this.maxPendingPerGuest = 3,
    this.maxGuests = 50,
    this.recentHistory = 20,
    this.votesEnabled = true,
  });

  /// Regles demandees par l'hote, ramenees dans des bornes raisonnables
  /// (un hote ne peut pas, par erreur, ouvrir 10 000 places).
  factory PartyRules.fromJson(Object? json) {
    if (json is! Map) return const PartyRules();
    int pick(String key, int fallback, int min, int max) {
      final value = json[key];
      return value is int ? value.clamp(min, max) : fallback;
    }

    return PartyRules(
      maxPendingPerGuest: pick('maxPendingPerGuest', 3, 1, 10),
      maxGuests: pick('maxGuests', 50, 1, 200),
      recentHistory: pick('recentHistory', 20, 0, 200),
      votesEnabled: json['votesEnabled'] is bool
          ? json['votesEnabled'] as bool
          : true,
    );
  }

  Map<String, dynamic> toJson() => {
        'maxPendingPerGuest': maxPendingPerGuest,
        'maxGuests': maxGuests,
        'recentHistory': recentHistory,
        'votesEnabled': votesEnabled,
      };
}

class PartyMember {
  final String id;
  final String name;
  final bool isHost;
  bool banned = false;

  PartyMember({required this.id, required this.name, required this.isHost});
}

class PartyItem {
  final String id;
  final PartySong song;
  final String memberId;

  /// Ordre d'arrivee global : departage les egalites dans un tour.
  final int seq;
  final Map<String, int> votes = {};

  PartyItem({
    required this.id,
    required this.song,
    required this.memberId,
    required this.seq,
  });

  int get score => votes.values.fold(0, (a, b) => a + b);
}

enum SuggestOutcome { accepted, limit, duplicate, banned }

class SuggestResult {
  final SuggestOutcome outcome;
  final PartyItem? item;
  const SuggestResult(this.outcome, [this.item]);
}

class Party {
  final String id;
  String code;
  final String name;
  final String ownerUser; // compte Navidrome de l'hote (limite par compte)
  final PartyRules rules;
  final DateTime expiresAt;
  final Map<String, PartyMember> members = {};
  final List<PartyItem> _items = [];

  /// songId des derniers titres joues, le plus recent en dernier.
  final List<String> _history = [];
  PartySong? nowPlaying;
  late final String hostId;
  int _seq = 0;
  int _ids = 0;

  Party({
    required this.id,
    required this.code,
    required this.name,
    required this.ownerUser,
    required this.rules,
    required this.expiresAt,
    required String hostName,
  }) {
    hostId = _newId('m');
    members[hostId] = PartyMember(id: hostId, name: hostName, isHost: true);
  }

  String _newId(String prefix) => '$prefix${++_ids}';

  int get guestCount =>
      members.values.where((m) => !m.isHost && !m.banned).length;

  bool get isFull => guestCount >= rules.maxGuests;

  PartyMember addGuest(String name) {
    final member = PartyMember(id: _newId('m'), name: name, isHost: false);
    members[member.id] = member;
    return member;
  }

  int pendingOf(String memberId) =>
      _items.where((i) => i.memberId == memberId).length;

  PartyItem? item(String itemId) {
    for (final i in _items) {
      if (i.id == itemId) return i;
    }
    return null;
  }

  SuggestResult suggest(String memberId, PartySong song) {
    final member = members[memberId];
    if (member == null || member.banned) {
      return const SuggestResult(SuggestOutcome.banned);
    }
    // Doublon : deja dans la file, en cours, ou joue il y a peu (sinon le
    // meme tube revient toutes les vingt minutes).
    final recent = rules.recentHistory == 0
        ? const <String>[]
        : _history.skip(
            (_history.length - rules.recentHistory).clamp(0, _history.length));
    if (_items.any((i) => i.song.songId == song.songId) ||
        nowPlaying?.songId == song.songId ||
        recent.contains(song.songId)) {
      return const SuggestResult(SuggestOutcome.duplicate);
    }
    if (!member.isHost && pendingOf(memberId) >= rules.maxPendingPerGuest) {
      return const SuggestResult(SuggestOutcome.limit);
    }
    final item = PartyItem(
      id: _newId('i'),
      song: song,
      memberId: memberId,
      seq: ++_seq,
    );
    _items.add(item);
    return SuggestResult(SuggestOutcome.accepted, item);
  }

  /// false si le titre n'est plus dans la file.
  bool vote(String memberId, String itemId, int value) {
    final target = item(itemId);
    if (target == null) return false;
    if (value == 0) {
      target.votes.remove(memberId);
    } else {
      target.votes[memberId] = value > 0 ? 1 : -1;
    }
    return true;
  }

  bool veto(String itemId) {
    final before = _items.length;
    _items.removeWhere((i) => i.id == itemId);
    return _items.length != before;
  }

  /// Exclut un membre : ses titres quittent la file et, s'il est banni, son
  /// jeton ne passe plus (voir PartyHub._memberFromToken).
  void kick(String memberId, {required bool ban}) {
    final member = members[memberId];
    if (member == null || member.isHost) return;
    _items.removeWhere((i) => i.memberId == memberId);
    if (ban) {
      member.banned = true;
    } else {
      members.remove(memberId);
    }
  }

  /// L'hote lance un titre : s'il vient de la file, il la quitte. Renvoie
  /// l'element de file joue, s'il y en avait un.
  PartyItem? play({String? itemId, PartySong? song}) {
    PartyItem? played;
    if (itemId != null) {
      played = item(itemId);
      if (played != null) _items.remove(played);
    }
    nowPlaying = played?.song ?? song;
    final id = nowPlaying?.songId;
    if (id != null) {
      _history.add(id);
      // Pas besoin de garder plus que ce que la regle des doublons regarde.
      if (_history.length > 200) _history.removeAt(0);
    }
    return played;
  }

  /// File dans l'ordre de passage : tour par tour entre les membres (tour 1
  /// = le premier titre en attente de chacun), puis le score des votes et
  /// l'ordre d'arrivee dans un meme tour. Ainsi un invite arrive tard passe
  /// devant le troisieme titre de quelqu'un d'autre.
  List<PartyItem> orderedQueue() {
    final rounds = <int, List<PartyItem>>{};
    final seen = <String, int>{};
    final byArrival = [..._items]..sort((a, b) => a.seq.compareTo(b.seq));
    for (final item in byArrival) {
      final round = seen[item.memberId] ?? 0;
      seen[item.memberId] = round + 1;
      rounds.putIfAbsent(round, () => []).add(item);
    }
    final ordered = <PartyItem>[];
    for (final round in rounds.keys.toList()..sort()) {
      final items = rounds[round]!
        ..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          return byScore != 0 ? byScore : a.seq.compareTo(b.seq);
        });
      ordered.addAll(items);
    }
    return ordered;
  }
}
