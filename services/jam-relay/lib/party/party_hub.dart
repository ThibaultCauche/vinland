// Messages du mode Soiree (voir docs/soiree-protocole.md). Independant du
// transport : bin/server.dart branche chaque connexion WebSocket sur une
// PartyConnection, et les tests utilisent de fausses connexions avec une
// horloge et un catalogue factices.
import 'dart:math';

import 'blind_test.dart';
import 'catalog.dart';
import 'party.dart';
import 'party_token.dart';
import 'rate_limiter.dart';

/// Version majeure du protocole (champ `v`).
const partyProtocolVersion = 1;

/// Ajouts au protocole annonces dans `party_joined` : l'app n'affiche une
/// fonction que si le relais la connait (un relais pas encore mis a jour
/// ignorerait ses messages sans rien dire).
const partyFeatures = ['blindtest'];

abstract class PartyConnection {
  void send(Map<String, dynamic> message);
  void close();
}

class PartyLimits {
  final Duration ttl;
  final int maxParties;
  final int maxPartiesPerUser;
  final int maxMessageChars;
  final int wrongCodesPerConnection;

  /// Hote sans identifiants Navidrome : seulement pour developper en local.
  final bool allowAnonymousHost;

  const PartyLimits({
    this.ttl = const Duration(hours: 6),
    this.maxParties = 20,
    this.maxPartiesPerUser = 3,
    this.maxMessageChars = 8 * 1024,
    this.wrongCodesPerConnection = 5,
    this.allowAnonymousHost = false,
  });
}

/// Ce que le hub sait d'une connexion entree dans une soiree.
class _Seat {
  final String partyId;
  final String memberId;
  final TokenBucket search;
  final TokenBucket suggest;
  final TokenBucket vote;
  _Seat(this.partyId, this.memberId, DateTime Function() now)
      : search = TokenBucket(capacity: 5, perSecond: 1, now: now),
        suggest = TokenBucket(capacity: 3, perSecond: 0.1, now: now),
        vote = TokenBucket(capacity: 10, perSecond: 2, now: now);
}

class PartyHub {
  static const _types = {
    'party_create',
    'party_join',
    'party_leave',
    'party_end',
    'party_rotate_code',
    'search',
    'suggest',
    'vote',
    'veto',
    'kick',
    'now_playing',
    'blindtest_start',
    'blindtest_round',
    'blindtest_reveal',
    'blindtest_stop',
    'blindtest_close',
    'blindtest_answer',
  };

  // Sans 0/O ni 1/I/L : se dicte sans ambiguite en soiree.
  static const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  final PartyTokenSigner signer;
  final PartyCatalog? catalog;
  final PartyLimits limits;
  final DateTime Function() _now;
  final Random _random;

  final Map<String, Party> _parties = {};
  final Map<String, String> _partyByCode = {};
  final Map<PartyConnection, _Seat> _seats = {};
  final Map<PartyConnection, int> _wrongCodes = {};

  /// Pochettes : un seau par membre, garde entre les requetes HTTP.
  final Map<String, TokenBucket> _coverBuckets = {};

  /// Essais rates (code faux, jeton faux, identifiants refuses) pour tout le
  /// relais : borne la force brute meme repartie sur plein de connexions.
  late final TokenBucket _failures;
  int _partyIds = 0;

  PartyHub({
    required this.signer,
    this.catalog,
    this.limits = const PartyLimits(),
    DateTime Function()? now,
    Random? random,
  })  : _now = now ?? DateTime.now,
        _random = random ?? Random.secure() {
    _failures = TokenBucket(capacity: 60, perSecond: 1, now: _now);
  }

  bool handles(Object? type) => _types.contains(type);

  int get partyCount => _parties.length;

  Party? partyByCode(String code) => _parties[_partyByCode[code]];

  Future<void> handle(
    PartyConnection conn,
    Map<String, dynamic> msg, {
    int rawLength = 0,
  }) async {
    if (rawLength > limits.maxMessageChars) {
      _error(conn, 'invalid', 'message trop long');
      return;
    }
    switch (msg['type']) {
      case 'party_create':
        return _create(conn, msg);
      case 'party_join':
        return _join(conn, msg);
      case 'party_leave':
        return _leave(conn);
      case 'search':
        return _search(conn, msg);
      case 'suggest':
        return _suggest(conn, msg);
      case 'vote':
        return _vote(conn, msg);
      case 'blindtest_answer':
        return _blindAnswer(conn, msg);
      case 'blindtest_start':
      case 'blindtest_round':
      case 'blindtest_reveal':
      case 'blindtest_stop':
      case 'blindtest_close':
      case 'veto':
      case 'kick':
      case 'now_playing':
      case 'party_rotate_code':
      case 'party_end':
        return _hostAction(conn, msg);
    }
  }

  /// Connexion fermee : le membre reste dans la soiree (il peut revenir avec
  /// son jeton), seuls les autres sont prevenus (hote hors ligne, etc.).
  void disconnected(PartyConnection conn) {
    _wrongCodes.remove(conn);
    final seat = _seats.remove(conn);
    if (seat == null) return;
    final party = _parties[seat.partyId];
    if (party != null) _broadcastQueue(party);
  }

  /// Termine les soirees expirees (appele toutes les 30 s par le serveur).
  void sweep() {
    final now = _now();
    for (final party in _parties.values.toList()) {
      if (!now.isBefore(party.expiresAt)) _end(party, 'expired');
    }
  }

  // --- Entree dans une soiree ---------------------------------------------

  Future<void> _create(PartyConnection conn, Map<String, dynamic> msg) async {
    if (!_checkVersion(conn, msg)) return;
    if (_seats.containsKey(conn)) {
      _error(conn, 'invalid', 'deja dans une soiree');
      return;
    }
    if (!_failures.hasToken) {
      _error(conn, 'rate_limited', 'trop de tentatives, reessaie plus tard');
      return;
    }
    final hostName = _text(msg['hostName'], 30);
    final name = _text(msg['name'], 60);
    if (hostName.isEmpty) {
      _error(conn, 'invalid', 'hostName manquant');
      return;
    }

    // Sans compte Navidrome valide, pas de soiree : sinon n'importe qui sur
    // Internet pourrait en ouvrir une et fouiller le catalogue par le relais.
    final auth = HostAuth.fromJson(msg['auth']);
    var ownerUser = auth?.user ?? '';
    if (!limits.allowAnonymousHost) {
      final cat = catalog;
      if (auth == null || cat == null || !await cat.verifyHost(auth)) {
        _failures.tryTake();
        _error(conn, 'unauthorized', 'identifiants Navidrome refuses');
        return;
      }
    } else if (ownerUser.isEmpty) {
      ownerUser = 'anonyme';
    }

    if (_parties.length >= limits.maxParties ||
        _parties.values.where((p) => p.ownerUser == ownerUser).length >=
            limits.maxPartiesPerUser) {
      _error(conn, 'full', 'trop de soirees ouvertes');
      return;
    }

    final party = Party(
      id: 'p${++_partyIds}-${_randomString(8, 'abcdefghijkmnpqrstuvwxyz23456789')}',
      code: _newCode(),
      name: name.isEmpty ? 'Soiree' : name,
      ownerUser: ownerUser,
      rules: PartyRules.fromJson(msg['rules']),
      expiresAt: _now().add(limits.ttl),
      hostName: hostName,
    );
    _parties[party.id] = party;
    _partyByCode[party.code] = party.id;
    _seat(conn, party, party.members[party.hostId]!);
  }

  Future<void> _join(PartyConnection conn, Map<String, dynamic> msg) async {
    if (!_checkVersion(conn, msg)) return;
    if (_seats.containsKey(conn)) {
      _error(conn, 'invalid', 'deja dans une soiree');
      return;
    }
    if (!_failures.hasToken) {
      _error(conn, 'rate_limited', 'trop de tentatives, reessaie plus tard');
      return;
    }

    final token = msg['token'];
    if (token is String && token.isNotEmpty) {
      final claims = signer.verify(token, _now());
      final party = claims == null ? null : _parties[claims.partyId];
      final member = party?.members[claims!.memberId];
      if (claims != null && party == null) {
        // Bien signe mais la soiree n'existe plus (terminee par l'hote).
        _error(conn, 'expired', 'soiree terminee');
        return;
      }
      if (party == null || member == null) {
        _wrongAttempt(conn, 'bad_token', 'jeton invalide');
        return;
      }
      if (member.banned) {
        _error(conn, 'banned', 'tu as ete exclu de cette soiree');
        return;
      }
      _seat(conn, party, member);
      return;
    }

    final code = _text(msg['code'], 12).toUpperCase();
    final party = partyByCode(code);
    if (party == null) {
      _wrongAttempt(conn, 'bad_code', 'code inconnu');
      return;
    }
    final name = _text(msg['name'], 30);
    if (name.isEmpty) {
      _error(conn, 'invalid', 'pseudo manquant');
      return;
    }
    if (party.isFull) {
      _error(conn, 'full', 'la soiree est complete');
      return;
    }
    _seat(conn, party, party.addGuest(name));
  }

  void _wrongAttempt(PartyConnection conn, String code, String message) {
    _failures.tryTake();
    final count = (_wrongCodes[conn] ?? 0) + 1;
    _wrongCodes[conn] = count;
    _error(conn, code, message);
    if (count >= limits.wrongCodesPerConnection) conn.close();
  }

  void _seat(PartyConnection conn, Party party, PartyMember member) {
    // Un membre qui revient (nouvelle connexion, meme jeton) remplace
    // l'ancienne connexion, restee peut-etre a moitie ouverte.
    for (final entry in _seats.entries.toList()) {
      if (entry.value.partyId == party.id &&
          entry.value.memberId == member.id) {
        _seats.remove(entry.key);
        entry.key.close();
      }
    }
    _seats[conn] = _Seat(party.id, member.id, _now);
    _wrongCodes.remove(conn);
    conn.send({
      'type': 'party_joined',
      'v': partyProtocolVersion,
      'partyId': party.id,
      'memberId': member.id,
      'role': member.isHost ? 'host' : 'guest',
      'name': party.name,
      'token': signer.sign(PartyClaims(
        partyId: party.id,
        memberId: member.id,
        role: member.isHost ? 'host' : 'guest',
        expiresAtMs: party.expiresAt.millisecondsSinceEpoch,
      )),
      'rules': party.rules.toJson(),
      'expiresAt': party.expiresAt.millisecondsSinceEpoch,
      'features': partyFeatures,
      if (member.isHost) 'code': party.code,
    });
    conn.send(_nowPlayingMessage(party));
    if (party.blindTest != null) {
      conn.send(_blindTestMessage(party, _seats[conn]!));
    }
    _broadcastQueue(party);
  }

  void _leave(PartyConnection conn) {
    final seat = _seats.remove(conn);
    if (seat == null) return;
    final party = _parties[seat.partyId];
    if (party != null) _broadcastQueue(party);
  }

  // --- Actions des membres ------------------------------------------------

  (Party, PartyMember, _Seat)? _member(PartyConnection conn) {
    final seat = _seats[conn];
    final party = seat == null ? null : _parties[seat.partyId];
    final member = party?.members[seat!.memberId];
    if (party == null || member == null || member.banned) {
      _error(conn, 'not_in_party', 'rejoins une soiree d\'abord');
      return null;
    }
    return (party, member, seat!);
  }

  Future<void> _search(PartyConnection conn, Map<String, dynamic> msg) async {
    final found = _member(conn);
    if (found == null) return;
    final (_, _, seat) = found;
    final requestId = msg['requestId'];
    final cat = catalog;
    if (cat == null) {
      _error(conn, 'search_unavailable', 'recherche non configuree',
          requestId: requestId);
      return;
    }
    final query = _text(msg['query'], 100);
    if (query.length < 2) {
      _error(conn, 'invalid', 'recherche trop courte', requestId: requestId);
      return;
    }
    if (!seat.search.tryTake()) {
      _error(conn, 'rate_limited', 'doucement', requestId: requestId);
      return;
    }
    final songs = await cat.search(query);
    conn.send({
      'type': 'search_results',
      'requestId': requestId,
      'songs': [
        for (final s in songs)
          {
            'id': s.songId,
            'title': s.title,
            'artist': s.artist,
            'album': s.album,
            'durationMs': s.durationMs,
            'coverId': s.coverId,
          }
      ],
    });
  }

  Future<void> _suggest(PartyConnection conn, Map<String, dynamic> msg) async {
    final found = _member(conn);
    if (found == null) return;
    final (party, member, seat) = found;
    final songId = _text(msg['songId'], 100);
    if (songId.isEmpty || !isSafeCatalogId(songId)) {
      _error(conn, 'invalid', 'songId manquant');
      return;
    }
    // L'hote remplit sa propre file comme il veut : pas de frein pour lui.
    if (!member.isHost && !seat.suggest.tryTake()) {
      _error(conn, 'rate_limited', 'doucement');
      return;
    }

    // Avec un catalogue, les infos viennent de Navidrome (un invite ne peut
    // pas afficher un faux titre dans la file) et le titre doit exister.
    final cat = catalog;
    final PartySong? song;
    if (cat != null) {
      song = await cat.song(songId);
      if (song == null) {
        _error(conn, 'not_found', 'titre introuvable');
        return;
      }
    } else {
      song = _songFromMessage(msg, songId);
    }
    // La soiree a pu se terminer pendant l'appel a Navidrome.
    if (!_parties.containsKey(party.id)) return;

    final result = party.suggest(member.id, song);
    switch (result.outcome) {
      case SuggestOutcome.accepted:
        conn.send({
          'type': 'suggested',
          'itemId': result.item!.id,
          'songId': songId,
        });
        _broadcastQueue(party);
      case SuggestOutcome.limit:
        _error(conn, 'limit',
            'deja ${party.rules.maxPendingPerGuest} titres en attente');
      case SuggestOutcome.duplicate:
        _error(conn, 'duplicate', 'ce titre est deja prevu ou vient de passer');
      case SuggestOutcome.banned:
        _error(conn, 'banned', 'tu as ete exclu de cette soiree');
    }
  }

  void _vote(PartyConnection conn, Map<String, dynamic> msg) {
    final found = _member(conn);
    if (found == null) return;
    final (party, member, seat) = found;
    if (!party.rules.votesEnabled) {
      _error(conn, 'forbidden', 'les votes sont desactives pour cette soiree');
      return;
    }
    final value = msg['value'];
    if (value is! int || value < -1 || value > 1) {
      _error(conn, 'invalid', 'vote = 1, -1 ou 0');
      return;
    }
    if (!seat.vote.tryTake()) {
      _error(conn, 'rate_limited', 'doucement');
      return;
    }
    if (!party.vote(member.id, _text(msg['itemId'], 40), value)) {
      _error(conn, 'not_found', 'ce titre n\'est plus dans la file');
      return;
    }
    _broadcastQueue(party);
  }

  // --- Actions de l'hote --------------------------------------------------

  void _hostAction(PartyConnection conn, Map<String, dynamic> msg) {
    final found = _member(conn);
    if (found == null) return;
    final (party, member, _) = found;
    if (!member.isHost) {
      _error(conn, 'forbidden', 'reserve a l\'hote');
      return;
    }
    switch (msg['type']) {
      case 'veto':
        if (!party.veto(_text(msg['itemId'], 40))) {
          _error(conn, 'not_found', 'ce titre n\'est plus dans la file');
          return;
        }
        _broadcastQueue(party);
      case 'kick':
        final targetId = _text(msg['memberId'], 40);
        final target = party.members[targetId];
        if (target == null || target.isHost) {
          _error(conn, 'not_found', 'invite introuvable');
          return;
        }
        final ban = msg['ban'] == true;
        party.kick(targetId, ban: ban);
        for (final entry in _seats.entries.toList()) {
          if (entry.value.partyId == party.id &&
              entry.value.memberId == targetId) {
            entry.key.send({'type': 'kicked', 'banned': ban});
            _seats.remove(entry.key);
            entry.key.close();
          }
        }
        _broadcastQueue(party);
      case 'now_playing':
        final itemId = msg['itemId'];
        if (itemId is String && itemId.isNotEmpty) {
          if (party.play(itemId: itemId) == null) {
            _error(conn, 'not_found', 'ce titre n\'est plus dans la file');
            return;
          }
        } else {
          final songId = _text(msg['songId'], 100);
          party.play(
              song: songId.isEmpty ? null : _songFromMessage(msg, songId),
              by: _text(msg['by'], 40));
        }
        _broadcast(party, (_) => _nowPlayingMessage(party));
        _broadcastQueue(party);
      case 'party_rotate_code':
        _partyByCode.remove(party.code);
        party.code = _newCode();
        _partyByCode[party.code] = party.id;
        conn.send({'type': 'party_code', 'code': party.code});
      case 'party_end':
        _end(party, 'host');
      case 'blindtest_start':
        final total = msg['rounds'];
        party.blindTest = BlindTest(total: total is int ? total : 10);
        _broadcastBlindTest(party);
      case 'blindtest_round':
        final test = party.blindTest;
        final choices = msg['choices'];
        final answer = msg['answer'];
        final duration = msg['durationMs'];
        final song = msg['song'];
        if (test == null ||
            choices is! List ||
            answer is! int ||
            !test.startRound(
              choices: [for (final c in choices) _text(c, 200)],
              answer: answer,
              duration:
                  Duration(milliseconds: duration is int ? duration : 20000),
              now: _now(),
              song: song is Map
                  ? _songFromMessage(song.cast<String, dynamic>(),
                          _text(song['songId'], 100))
                      .toJson()
                  : null,
            )) {
          _error(conn, 'invalid', 'manche invalide');
          return;
        }
        _broadcastBlindTest(party);
      case 'blindtest_reveal':
        party.blindTest?.reveal();
        _broadcastBlindTest(party);
      case 'blindtest_stop':
        party.blindTest?.finish();
        _broadcastBlindTest(party);
      case 'blindtest_close':
        party.blindTest = null;
        _broadcast(party, (_) => {'type': 'blindtest_state', 'active': false});
    }
  }

  void _blindAnswer(PartyConnection conn, Map<String, dynamic> msg) {
    final found = _member(conn);
    if (found == null) return;
    final (party, member, seat) = found;
    final test = party.blindTest;
    if (member.isHost) {
      _error(conn, 'forbidden', 'l\'hote connait deja la reponse');
      return;
    }
    if (test == null) {
      _error(conn, 'not_found', 'pas de blind test en cours');
      return;
    }
    if (!seat.vote.tryTake()) {
      _error(conn, 'rate_limited', 'doucement');
      return;
    }
    final round = msg['round'], choice = msg['choice'];
    if (round is! int || choice is! int) {
      _error(conn, 'invalid', 'round et choice attendus');
      return;
    }
    switch (test.answer(member.id, round, choice, _now())) {
      case BlindAnswerOutcome.accepted:
        _broadcastBlindTest(party);
      case BlindAnswerOutcome.already:
        _error(conn, 'duplicate', 'tu as deja repondu');
      case BlindAnswerOutcome.closed:
        _error(conn, 'expired', 'trop tard pour cette manche');
      case BlindAnswerOutcome.invalid:
        _error(conn, 'invalid', 'choix inconnu');
    }
  }

  void _end(Party party, String reason) {
    _parties.remove(party.id);
    _partyByCode.remove(party.code);
    for (final m in party.members.keys) {
      _coverBuckets.remove('${party.id}/$m');
    }
    for (final entry in _seats.entries.toList()) {
      if (entry.value.partyId != party.id) continue;
      entry.key.send({'type': 'party_ended', 'reason': reason});
      _seats.remove(entry.key);
      entry.key.close();
    }
  }

  // --- Pochettes (HTTP) ---------------------------------------------------

  /// Pochette pour un porteur de jeton. Renvoie un code HTTP et l'image.
  Future<(int, CoverImage?)> cover(
    String? bearerToken,
    String coverId,
    int size,
  ) async {
    final claims =
        bearerToken == null ? null : signer.verify(bearerToken, _now());
    final party = claims == null ? null : _parties[claims.partyId];
    final member = party?.members[claims!.memberId];
    if (member == null || member.banned) return (401, null);
    final cat = catalog;
    if (cat == null) return (404, null);
    if (!isSafeCatalogId(coverId)) return (400, null);
    final bucket = _coverBuckets.putIfAbsent('${party!.id}/${member.id}',
        () => TokenBucket(capacity: 30, perSecond: 5, now: _now));
    if (!bucket.tryTake()) return (429, null);
    final image = await cat.cover(coverId, size.clamp(32, 600));
    return image == null ? (404, null) : (200, image);
  }

  // --- Diffusion ----------------------------------------------------------

  void _broadcastBlindTest(Party party) {
    if (party.blindTest == null) return;
    _broadcast(party, (seat) => _blindTestMessage(party, seat));
  }

  /// Etat du blind test vu par [seat] : la reponse n'est donnee qu'a l'hote
  /// avant la revelation.
  Map<String, dynamic> _blindTestMessage(Party party, _Seat seat) {
    final test = party.blindTest!;
    final round = test.round;
    final isHost = seat.memberId == party.hostId;
    final shown = round != null && (round.revealed || isHost);
    final phase = test.over
        ? 'over'
        : round == null
            ? 'ready'
            : round.revealed
                ? 'reveal'
                : 'question';
    final players = [
      for (final m in party.members.values)
        if (!m.isHost && !m.banned) m
    ];
    final scores = [
      for (final m in players)
        {'memberId': m.id, 'name': m.name, 'points': test.scores[m.id] ?? 0}
    ]..sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));
    return {
      'type': 'blindtest_state',
      'active': true,
      'phase': phase,
      'total': test.total,
      'scores': scores,
      'players': players.length,
      if (round != null) ...{
        'round': round.number,
        'choices': round.choices,
        'durationMs': round.duration.inMilliseconds,
        'remainingMs': round.revealed
            ? 0
            : round.endsAt
                .difference(_now())
                .inMilliseconds
                .clamp(0, round.duration.inMilliseconds),
        'answered': round.answers.length,
        if (round.answers[seat.memberId] != null)
          'myChoice': round.answers[seat.memberId],
        if (shown) 'answer': round.answer,
        if (shown && round.song != null) 'song': round.song,
        if (round.revealed && round.gained[seat.memberId] != null)
          'myGained': round.gained[seat.memberId],
      },
    };
  }

  Map<String, dynamic> _nowPlayingMessage(Party party) => {
        'type': 'now_playing',
        'song': party.nowPlaying?.toJson(),
        'by': party.nowPlayingBy,
      };

  void _broadcast(
    Party party,
    Map<String, dynamic> Function(_Seat seat) build,
  ) {
    for (final entry in _seats.entries.toList()) {
      if (entry.value.partyId == party.id) entry.key.send(build(entry.value));
    }
  }

  /// File personnalisee pour chacun (son vote, ses titres) ; l'hote recoit
  /// en plus la liste des membres pour pouvoir exclure quelqu'un.
  void _broadcastQueue(Party party) {
    final online = {
      for (final s in _seats.values)
        if (s.partyId == party.id) s.memberId
    };
    final queue = party.orderedQueue();
    _broadcast(party, (seat) {
      final isHost = seat.memberId == party.hostId;
      return {
        'type': 'queue_state',
        'items': [
          for (final item in queue)
            {
              'id': item.id,
              ...item.song.toJson(),
              'by': party.members[item.memberId]?.name ?? '',
              'byId': item.memberId,
              'score': item.score,
              'myVote': item.votes[seat.memberId] ?? 0,
              'mine': item.memberId == seat.memberId,
            }
        ],
        'guestCount': party.guestCount,
        'hostOnline': online.contains(party.hostId),
        if (isHost)
          'members': [
            for (final m in party.members.values)
              if (!m.isHost && !m.banned)
                {
                  'id': m.id,
                  'name': m.name,
                  'online': online.contains(m.id),
                  'pending': party.pendingOf(m.id),
                }
          ],
      };
    });
  }

  // --- Utilitaires --------------------------------------------------------

  bool _checkVersion(PartyConnection conn, Map<String, dynamic> msg) {
    final v = msg['v'];
    if (v is int && v > partyProtocolVersion) {
      _error(conn, 'version',
          'relais trop ancien (protocole $partyProtocolVersion), mets-le a jour');
      return false;
    }
    return true;
  }

  PartySong _songFromMessage(Map<String, dynamic> msg, String songId) {
    final duration = msg['durationMs'];
    final coverId = _text(msg['coverId'], 100);
    return PartySong(
      songId: songId,
      title: _text(msg['title'], 200),
      artist: _text(msg['artist'], 200),
      album: _text(msg['album'], 200),
      durationMs: duration is int ? duration.clamp(0, 24 * 3600 * 1000) : 0,
      coverId: coverId.isEmpty || !isSafeCatalogId(coverId) ? null : coverId,
    );
  }

  static String _text(Object? value, int max) {
    if (value is! String) return '';
    final trimmed = value.trim();
    return trimmed.length > max ? trimmed.substring(0, max) : trimmed;
  }

  String _newCode() {
    while (true) {
      final code = _randomString(6, _codeAlphabet);
      if (!_partyByCode.containsKey(code)) return code;
    }
  }

  String _randomString(int length, String alphabet) =>
      List.generate(length, (_) => alphabet[_random.nextInt(alphabet.length)])
          .join();

  void _error(
    PartyConnection conn,
    String code,
    String message, {
    Object? requestId,
  }) {
    conn.send({
      'type': 'party_error',
      'code': code,
      'message': message,
      if (requestId != null) 'requestId': requestId,
    });
  }
}
