import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/blind_test_host.dart';
import '../../controllers/party_controller.dart';
import '../../services/party/party_models.dart';
import 'party_widgets.dart';

/// Couleurs des 4 reponses, comme sur une telecommande de jeu : on dit
/// « le rouge ! » plus vite que « la troisieme ».
const blindTestColors = [
  Color(0xFFE53935),
  Color(0xFF1E88E5),
  Color(0xFFFDD835),
  Color(0xFF43A047),
  Color(0xFF8E24AA),
  Color(0xFFFB8C00),
];

Color _onColor(Color c) =>
    c.computeLuminance() > 0.5 ? Colors.black : Colors.white;

/// Reglages d'un blind test, demandes a l'hote avant de lancer.
Future<void> showBlindTestSetup(
    BuildContext context, BlindTestHost host) async {
  var rounds = 10;
  var seconds = 20;
  final start = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: partySurface,
        title: const Text('Blind test', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Un extrait passe sur ton enceinte, les invités choisissent la '
              'bonne réponse sur leur téléphone. Plus on répond vite, plus on '
              'marque. La file de la soirée attend la fin du jeu.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            const Text('Manches', style: partyMuted),
            Wrap(spacing: 8, children: [
              for (final n in const [5, 10, 15, 20])
                ChoiceChip(
                  label: Text('$n'),
                  selected: rounds == n,
                  onSelected: (_) => setState(() => rounds = n),
                ),
            ]),
            const SizedBox(height: 12),
            const Text('Durée de l\'extrait', style: partyMuted),
            Wrap(spacing: 8, children: [
              for (final s in const [10, 15, 20, 30])
                ChoiceChip(
                  label: Text('$s s'),
                  selected: seconds == s,
                  onSelected: (_) => setState(() => seconds = s),
                ),
            ]),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Lancer')),
        ],
      ),
    ),
  );
  if (start != true || !context.mounted) return;
  final ok = host.start(rounds: rounds, extract: Duration(seconds: seconds));
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Pas assez de titres d\'artistes différents sur le NAS '
          'pour un blind test.'),
    ));
  }
}

/// Secondes restantes avant [endsAt], rafraichies tant que le chrono tourne.
class BlindTestCountdown extends StatefulWidget {
  const BlindTestCountdown({
    super.key,
    required this.endsAt,
    required this.duration,
    this.size = 56,
  });

  final DateTime? endsAt;
  final Duration duration;
  final double size;

  @override
  State<BlindTestCountdown> createState() => _BlindTestCountdownState();
}

class _BlindTestCountdownState extends State<BlindTestCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
        const Duration(milliseconds: 250), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final end = widget.endsAt;
    final left = end == null
        ? Duration.zero
        : end.difference(DateTime.now()).isNegative
            ? Duration.zero
            : end.difference(DateTime.now());
    final total = widget.duration.inMilliseconds;
    final progress = total == 0 ? 0.0 : left.inMilliseconds / total;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: widget.size / 12,
              color: progress < 0.25 ? Colors.redAccent : partyAccent,
              backgroundColor: Colors.white12,
            ),
          ),
          Text('${(left.inMilliseconds / 1000).ceil()}',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.size * 0.4,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Classement : [limit] premiers, [me] mis en avant.
class BlindTestScoreboard extends StatelessWidget {
  const BlindTestScoreboard({
    super.key,
    required this.scores,
    this.me,
    this.limit,
    this.scale = 1,
  });

  final List<BlindTestScore> scores;
  final String? me;
  final int? limit;
  final double scale;

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    final shown = limit == null ? scores : scores.take(limit!).toList();
    if (shown.isEmpty) {
      return const Text('Aucun joueur pour le moment.', style: partyMuted);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in shown.indexed)
          Container(
            margin: EdgeInsets.symmetric(vertical: 3 * scale),
            padding: EdgeInsets.symmetric(
                horizontal: 12 * scale, vertical: 8 * scale),
            decoration: BoxDecoration(
              color: s.memberId == me
                  ? partyAccent.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 36 * scale,
                  child: Text(i < 3 ? _medals[i] : '${i + 1}',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 18 * scale,
                          fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: Text(s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16 * scale,
                          fontWeight: FontWeight.w600)),
                ),
                Text('${s.points} pts',
                    style: TextStyle(
                        color: partyAccent,
                        fontSize: 16 * scale,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Une reponse : couleur, texte, et son etat (choisie, bonne, fausse).
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.index,
    required this.label,
    required this.state,
    this.onTap,
  });

  final int index;
  final String label;
  final BlindTestState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = blindTestColors[index % blindTestColors.length];
    final answer = state.answer;
    final chosen = state.myChoice == index;
    final revealed = answer != null &&
        (state.phase == BlindTestPhase.reveal ||
            state.phase == BlindTestPhase.over);
    final isAnswer = answer == index;
    // Apres la reponse ou la revelation, les autres choix s'effacent.
    final dimmed = (state.myChoice != null && !chosen && !revealed) ||
        (revealed && !isAnswer);
    return Opacity(
      opacity: dimmed ? 0.35 : 1,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey('blindtest-choice-$index'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: chosen || (revealed && isAnswer)
                  ? Border.all(color: Colors.white, width: 3)
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: _onColor(color),
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
                if (revealed && isAnswer)
                  Icon(Icons.check_circle, color: _onColor(color))
                else if (chosen)
                  Icon(Icons.touch_app, color: _onColor(color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Invite pendant un blind test : la question, sa reponse, puis le
/// classement.
class BlindTestGuestView extends StatelessWidget {
  const BlindTestGuestView({super.key, required this.party});

  final PartyController party;

  @override
  Widget build(BuildContext context) {
    final state = party.blindTest!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header(state),
        const SizedBox(height: 16),
        if (state.phase == BlindTestPhase.ready)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('Prépare-toi, la première manche arrive !',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ),
        if (state.phase == BlindTestPhase.question ||
            state.phase == BlindTestPhase.reveal) ...[
          for (final (i, label) in state.choices.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ChoiceButton(
                index: i,
                label: label,
                state: state,
                onTap: state.phase == BlindTestPhase.question &&
                        state.myChoice == null
                    ? () => party.answerBlindTest(i)
                    : null,
              ),
            ),
          const SizedBox(height: 8),
          _status(state),
        ],
        if (state.phase == BlindTestPhase.reveal ||
            state.phase == BlindTestPhase.over) ...[
          const SizedBox(height: 24),
          Text(
              state.phase == BlindTestPhase.over
                  ? 'Classement final'
                  : 'Classement',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          BlindTestScoreboard(scores: state.scores, me: party.memberId),
        ],
      ],
    );
  }

  Widget _header(BlindTestState state) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🎵 Blind test',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                if (state.round > 0)
                  Text('Manche ${state.round} sur ${state.total}',
                      style: partyMuted),
              ],
            ),
          ),
          if (state.phase == BlindTestPhase.question)
            BlindTestCountdown(endsAt: state.endsAt, duration: state.duration),
        ],
      );

  Widget _status(BlindTestState state) {
    final String text;
    if (state.phase == BlindTestPhase.question) {
      text = state.myChoice == null
          ? 'Écoute bien et choisis !'
          : 'Réponse envoyée, attends la révélation…';
    } else {
      final gained = state.myGained;
      text = gained == null
          ? 'Pas de réponse cette fois.'
          : gained > 0
              ? 'Bravo ! +$gained points'
              : 'Raté !';
    }
    final song = state.song;
    return Column(
      children: [
        Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        if (state.phase == BlindTestPhase.reveal && song != null) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PartyCover(coverId: song.coverId, size: 56),
              const SizedBox(width: 12),
              Flexible(
                child: Text('${song.title}\n${song.artist}',
                    style: const TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Hote pendant un blind test : la reponse (il passe le titre), qui a
/// repondu, et les boutons pour avancer.
class BlindTestHostPanel extends StatelessWidget {
  const BlindTestHostPanel(
      {super.key, required this.party, required this.host});

  final PartyController party;
  final BlindTestHost host;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: host,
      builder: (context, _) {
        final state = party.blindTest;
        if (state == null) return const SizedBox();
        final current = host.current;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🎵 Blind test',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800)),
                      Text(
                          state.round == 0
                              ? '${state.total} manches · ${state.players} joueurs'
                              : 'Manche ${state.round} sur ${state.total} · '
                                  '${state.answered}/${state.players} réponses',
                          style: partyMuted),
                    ],
                  ),
                ),
                if (state.phase == BlindTestPhase.question)
                  BlindTestCountdown(
                      endsAt: state.endsAt, duration: state.duration),
              ],
            ),
            const SizedBox(height: 16),
            if (state.phase == BlindTestPhase.question ||
                state.phase == BlindTestPhase.reveal)
              for (final (i, label) in state.choices.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ChoiceButton(
                    index: i,
                    label: label,
                    state: BlindTestState(
                      phase: BlindTestPhase.reveal,
                      answer: state.answer,
                    ),
                  ),
                ),
            if (current != null && state.phase == BlindTestPhase.question)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Réponse : ${BlindTestHost.label(current.track)}',
                    style: partyMuted),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (state.phase == BlindTestPhase.question)
                  FilledButton.icon(
                    onPressed: host.reveal,
                    icon: const Icon(Icons.visibility),
                    label: const Text('Révéler'),
                  ),
                if (host.hasNextRound && state.phase != BlindTestPhase.question)
                  FilledButton.icon(
                    key: const ValueKey('blindtest-next'),
                    style: FilledButton.styleFrom(backgroundColor: partyAccent),
                    onPressed: host.nextRound,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(state.round == 0
                        ? 'Première manche'
                        : 'Manche suivante'),
                  ),
                if (host.isRunning &&
                    !host.hasNextRound &&
                    state.phase == BlindTestPhase.reveal)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: partyAccent),
                    onPressed: host.stop,
                    icon: const Icon(Icons.emoji_events),
                    label: const Text('Résultats'),
                  ),
                if (host.isRunning && state.phase != BlindTestPhase.over)
                  OutlinedButton(
                    onPressed: host.stop,
                    child: const Text('Arrêter'),
                  ),
                if (state.phase == BlindTestPhase.over)
                  FilledButton.icon(
                    onPressed: host.close,
                    icon: const Icon(Icons.queue_music),
                    label: const Text('Retour à la soirée'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
                state.phase == BlindTestPhase.over
                    ? 'Classement final'
                    : 'Classement',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            BlindTestScoreboard(scores: state.scores),
          ],
        );
      },
    );
  }
}

/// Ecran d'ambiance (tele) pendant un blind test : chrono et reponses
/// pendant la manche, reponse et podium ensuite.
class BlindTestAmbiance extends StatelessWidget {
  const BlindTestAmbiance(
      {super.key, required this.state, required this.scale});

  final BlindTestState state;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final song = state.song;
    final revealed = state.phase == BlindTestPhase.reveal ||
        state.phase == BlindTestPhase.over;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          state.phase == BlindTestPhase.over
              ? '🏆 Résultats du blind test'
              : state.round == 0
                  ? '🎵 Blind test : ça commence !'
                  : '🎵 Blind test · manche ${state.round}/${state.total}',
          style: TextStyle(
              color: Colors.white,
              fontSize: 36 * scale,
              fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 24 * scale),
        if (state.phase == BlindTestPhase.question)
          Row(
            children: [
              BlindTestCountdown(
                  endsAt: state.endsAt,
                  duration: state.duration,
                  size: 120 * scale),
              SizedBox(width: 32 * scale),
              Text('${state.answered}/${state.players}\nont répondu',
                  style:
                      TextStyle(color: Colors.white70, fontSize: 28 * scale)),
            ],
          ),
        if (state.phase == BlindTestPhase.reveal && song != null)
          Row(
            children: [
              PartyCover(coverId: song.coverId, size: 140 * scale, radius: 12),
              SizedBox(width: 24 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 34 * scale,
                            fontWeight: FontWeight.w800)),
                    Text(song.artist,
                        style: TextStyle(
                            color: Colors.white70, fontSize: 26 * scale)),
                  ],
                ),
              ),
            ],
          ),
        if (revealed) ...[
          SizedBox(height: 24 * scale),
          BlindTestScoreboard(
            scores: state.scores,
            limit: state.phase == BlindTestPhase.over ? 10 : 5,
            scale: scale * 1.4,
          ),
        ],
      ],
    );
  }
}
