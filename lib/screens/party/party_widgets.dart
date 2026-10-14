import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/party_controller.dart';
import '../../services/party/party_link.dart';
import '../../services/party/party_models.dart';
import '../../providers/app_state.dart';
import '../../widgets/app_background.dart';
import 'party_recap.dart';

// Morceaux communs aux ecrans du mode Soiree (hote et invite).

// Memes couleurs que le reste de l'app : le fond choisi dans Parametres >
// Personnalisation (voir PlatformBackground), les cartes grises et le vert
// Vinland.
const partyBackground = Colors.transparent;
const partySurface = Color(0xFF2A2A2A);
const partyAccent = Color(0xFF1DB954);
const partyMuted = TextStyle(color: Colors.white54, fontSize: 13);

/// Fond des ecrans de soiree : celui du reste de l'app (Parametres >
/// Personnalisation), ou le gris de l'app sans etat charge (tests).
class PartyBackground extends StatelessWidget {
  const PartyBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Provider.of<AppState?>(context, listen: false) == null) {
      return ColoredBox(color: const Color(0xFF121212), child: child);
    }
    return PlatformBackground(child: child);
  }
}

AppBar partyAppBar(String title,
        {List<Widget>? actions, PreferredSizeWidget? bottom}) =>
    AppBar(
      backgroundColor: partyBackground,
      foregroundColor: Colors.white,
      title: Text(title),
      actions: actions,
      bottom: bottom,
    );

String formatPartyDuration(int ms) {
  if (ms <= 0) return '';
  final total = ms ~/ 1000;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// Pochette servie par le relais (les invites n'ont pas de compte
/// Navidrome), en [px] pixels de cote ; null sans pochette ou hors soiree.
ImageProvider? partyCoverImage(PartyController party, String? coverId, int px) {
  final relay = party.relayUrl, token = party.token;
  if (coverId == null || relay == null || token == null) return null;
  return NetworkImage(
    partyCoverUri(relay, coverId, size: px.clamp(32, 600)).toString(),
    headers: {'Authorization': 'Bearer $token'},
  );
}

/// Pochette servie par le relais ; un carre neutre si pas de pochette ou en
/// cas d'erreur.
class PartyCover extends StatelessWidget {
  const PartyCover(
      {super.key, required this.coverId, this.size = 48, this.radius = 4});

  final String? coverId;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final party = context.read<PartyController>();
    final placeholder = Container(
      width: size,
      height: size,
      color: const Color(0xFF2A2A2A),
      child: Icon(Icons.music_note, color: Colors.white24, size: size * 0.5),
    );
    // Pochette demandee deja reduite (2x pour les ecrans denses).
    final image = partyCoverImage(party, coverId, (size * 2).round());
    if (image == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image(
        image: image,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}

/// Le titre qui passe sur l'enceinte de l'hote.
class PartyNowPlayingCard extends StatelessWidget {
  const PartyNowPlayingCard({super.key, required this.song});

  final PartySong? song;

  @override
  Widget build(BuildContext context) {
    final current = song;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: partySurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          PartyCover(coverId: current?.coverId, size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('EN CE MOMENT',
                    style: TextStyle(
                        color: partyAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text(
                  current?.title ?? 'Rien pour le moment',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                if (current != null)
                  Text(current.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: partyMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Une proposition de la file : qui l'a proposee, son score, et selon le
/// role les votes (invite) ou veto / lecture immediate (hote).
class PartyQueueTile extends StatelessWidget {
  const PartyQueueTile({
    super.key,
    required this.item,
    required this.position,
    required this.votesEnabled,
    this.onVote,
    this.onVeto,
    this.onPlayNow,
  });

  final PartyQueueItem item;
  final int position;
  final bool votesEnabled;
  final void Function(int value)? onVote;
  final VoidCallback? onVeto;
  final VoidCallback? onPlayNow;

  @override
  Widget build(BuildContext context) {
    final song = item.song;
    final by = item.mine ? 'toi' : item.by;
    return ListTile(
      key: ValueKey('party-item-${item.id}'),
      leading: PartyCover(coverId: song.coverId),
      title: Text(song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        '${song.artist} · proposé par $by',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: partyMuted,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (votesEnabled) ...[
            if (onVote != null)
              _VoteButton(
                icon: Icons.thumb_up,
                active: item.myVote == 1,
                tooltip: "J'aime",
                onTap: () => onVote!(item.myVote == 1 ? 0 : 1),
              ),
            SizedBox(
              width: 28,
              child: Text(
                item.score > 0 ? '+${item.score}' : '${item.score}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: item.score > 0
                      ? partyAccent
                      : item.score < 0
                          ? Colors.redAccent
                          : Colors.white54,
                ),
              ),
            ),
            if (onVote != null)
              _VoteButton(
                icon: Icons.thumb_down,
                active: item.myVote == -1,
                tooltip: "Pas maintenant",
                onTap: () => onVote!(item.myVote == -1 ? 0 : -1),
              ),
          ],
          if (onPlayNow != null)
            IconButton(
              tooltip: 'Jouer maintenant',
              icon: const Icon(Icons.play_arrow, color: Colors.white),
              onPressed: onPlayNow,
            ),
          if (onVeto != null)
            IconButton(
              tooltip: 'Retirer (veto)',
              icon: const Icon(Icons.block, color: Colors.redAccent),
              onPressed: onVeto,
            ),
        ],
      ),
    );
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        icon:
            Icon(icon, size: 20, color: active ? partyAccent : Colors.white38),
        onPressed: onTap,
      );
}

/// Bandeau quand la connexion au relais est perdue (reconnexion auto) ou
/// que l'hote est hors ligne.
class PartyStatusBanner extends StatelessWidget {
  const PartyStatusBanner({super.key, required this.party});

  final PartyController party;

  @override
  Widget build(BuildContext context) {
    String? text;
    if (party.phase == PartyPhase.reconnecting) {
      text = 'Connexion perdue, on revient tout seul…';
    } else if (!party.isHost && !party.queue.hostOnline) {
      text = "L'hôte est hors ligne pour le moment.";
    }
    if (text == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: const Color(0xFF2A2A2A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }
}

/// Montre en bas d'ecran les messages passagers du controleur (titre
/// propose, doublon refuse...).
class PartyNoticeListener extends StatefulWidget {
  const PartyNoticeListener(
      {super.key, required this.party, required this.child});

  final PartyController party;
  final Widget child;

  @override
  State<PartyNoticeListener> createState() => _PartyNoticeListenerState();
}

class _PartyNoticeListenerState extends State<PartyNoticeListener> {
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.party.notices.listen((text) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(text),
          backgroundColor: const Color(0xFF2A2A2A),
          duration: const Duration(seconds: 2),
        ));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Ecran de fin (soiree terminee, exclu, quittee).
class PartyEndedView extends StatelessWidget {
  const PartyEndedView({super.key, required this.party});

  final PartyController party;

  static String message(PartyEndReason? reason) => switch (reason) {
        PartyEndReason.host =>
          "L'hôte a terminé la soirée. Merci d'être venu !",
        PartyEndReason.expired => 'La soirée est terminée.',
        PartyEndReason.kicked => "L'hôte t'a retiré de la soirée.",
        PartyEndReason.banned => "L'hôte t'a exclu de la soirée.",
        PartyEndReason.left => 'Tu as quitté la soirée.',
        PartyEndReason.lost ||
        null =>
          "La soirée n'existe plus (le relais a peut-être redémarré).",
      };

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.nightlife, color: partyAccent, size: 56),
              const SizedBox(height: 16),
              Text(
                message(party.endReason),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 17),
              ),
              if (party.isHost) PartyRecapCard(party: party),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  party.clear();
                  Navigator.of(context).maybePop();
                },
                child: const Text('Fermer'),
              ),
            ],
          ),
        ),
      );
}
