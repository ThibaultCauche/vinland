// Blind test du mode Soiree (voir docs/soiree-protocole.md, « Blind
// test »). Logique pure, sans reseau ni minuterie : PartyHub donne l'heure.
//
// L'hote joue un extrait sur son enceinte et envoie au relais 4 choix et la
// bonne reponse ; le relais garde la reponse secrete, note qui a repondu
// quoi et quand, puis la devoile quand l'hote le demande. Les points
// recompensent la bonne reponse et la vitesse.

/// Une manche : les choix montres, la reponse (secrete jusqu'a la
/// revelation) et ce que chacun a repondu.
class BlindTestRound {
  final int number;
  final List<String> choices;
  final int answer;
  final DateTime startedAt;
  final Duration duration;

  /// Titre a devoiler a la fin de la manche (titre, artiste, pochette).
  final Map<String, dynamic>? song;

  /// memberId -> choix.
  final Map<String, int> answers = {};

  /// memberId -> points gagnes pendant cette manche.
  final Map<String, int> gained = {};
  bool revealed = false;

  BlindTestRound({
    required this.number,
    required this.choices,
    required this.answer,
    required this.startedAt,
    required this.duration,
    this.song,
  });

  DateTime get endsAt => startedAt.add(duration);
}

enum BlindAnswerOutcome { accepted, already, closed, invalid }

class BlindTest {
  /// Nombre de manches prevues (1 a 50).
  final int total;

  /// memberId -> points cumules.
  final Map<String, int> scores = {};
  BlindTestRound? round;
  bool over = false;

  /// Points d'une bonne reponse donnee a la derniere seconde ; jusqu'au
  /// double pour une reponse immediate.
  static const basePoints = 100;

  /// Marge apres la fin du chrono : le message part du telephone a temps
  /// mais arrive un peu apres.
  static const grace = Duration(milliseconds: 800);

  BlindTest({required int total}) : total = total.clamp(1, 50);

  /// Nouvelle manche. False si les donnees ne tiennent pas debout.
  bool startRound({
    required List<String> choices,
    required int answer,
    required Duration duration,
    required DateTime now,
    Map<String, dynamic>? song,
  }) {
    if (over) return false;
    if (choices.length < 2 || choices.length > 6) return false;
    if (answer < 0 || answer >= choices.length) return false;
    final number = (round?.number ?? 0) + 1;
    if (number > total) return false;
    round = BlindTestRound(
      number: number,
      choices: choices,
      answer: answer,
      startedAt: now,
      duration:
          Duration(milliseconds: duration.inMilliseconds.clamp(5000, 60000)),
      song: song,
    );
    return true;
  }

  BlindAnswerOutcome answer(
      String memberId, int roundNumber, int choice, DateTime now) {
    final r = round;
    if (r == null || r.number != roundNumber || r.revealed) {
      return BlindAnswerOutcome.closed;
    }
    if (now.isAfter(r.endsAt.add(grace))) return BlindAnswerOutcome.closed;
    if (choice < 0 || choice >= r.choices.length) {
      return BlindAnswerOutcome.invalid;
    }
    if (r.answers.containsKey(memberId)) return BlindAnswerOutcome.already;
    r.answers[memberId] = choice;
    if (choice == r.answer) {
      final left = r.endsAt.difference(now).inMilliseconds;
      final ratio = (left / r.duration.inMilliseconds).clamp(0.0, 1.0);
      r.gained[memberId] = basePoints + (basePoints * ratio).round();
    } else {
      r.gained[memberId] = 0;
    }
    return BlindAnswerOutcome.accepted;
  }

  /// Devoile la reponse et ajoute les points de la manche. Sans effet si
  /// deja fait.
  void reveal() {
    final r = round;
    if (r == null || r.revealed) return;
    r.revealed = true;
    r.gained.forEach((member, points) {
      scores.update(member, (s) => s + points, ifAbsent: () => points);
    });
  }

  /// Fin du blind test (derniere manche jouee ou arret par l'hote) : la
  /// manche en cours est devoilee, le classement reste affiche.
  void finish() {
    reveal();
    over = true;
  }

  /// Un membre exclu sort du classement.
  void forget(String memberId) {
    scores.remove(memberId);
    round?.answers.remove(memberId);
    round?.gained.remove(memberId);
  }
}
