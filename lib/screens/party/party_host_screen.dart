import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/party_controller.dart';
import '../../controllers/party_environment.dart';
import '../../services/party/party_link.dart';
import '../../services/party/party_models.dart';
import 'party_ambiance_screen.dart';
import 'party_offline_pack_screen.dart';
import 'party_qr_screen.dart';
import 'party_widgets.dart';

/// Hote pendant la soiree : code et QR a montrer, file avec qui a propose
/// quoi (veto, lecture immediate), invites (retirer, exclure). Quitter cet
/// ecran ne termine pas la soiree : la musique continue et on y revient par
/// le menu Jam.
class PartyHostScreen extends StatelessWidget {
  const PartyHostScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final party = context.watch<PartyController>();
    if (party.phase == PartyPhase.ended || party.phase == PartyPhase.idle) {
      return Scaffold(
        backgroundColor: partyBackground,
        appBar: partyAppBar('Soirée'),
        body: PartyEndedView(party: party),
      );
    }
    final guests = party.queue.members;
    final env = context.read<PartyEnvironment>();
    return PartyNoticeListener(
      party: party,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: partyBackground,
          appBar: partyAppBar(
            party.partyName.isEmpty ? 'Soirée' : party.partyName,
            actions: [
              IconButton(
                tooltip: "Écran d'ambiance",
                icon: const Icon(Icons.tv),
                onPressed: () => openPartyAmbiance(context),
              ),
              IconButton(
                tooltip: 'Afficher le QR code',
                icon: const Icon(Icons.qr_code_2),
                onPressed: () => _showQr(context, party),
              ),
              PopupMenuButton<String>(
                onSelected: (value) => switch (value) {
                  'radio' => env.setRadioEnabled
                      ?.call(!(env.radioEnabled?.call() ?? false)),
                  'pack' => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PartyOfflinePackScreen())),
                  'code' => _rotateCode(context, party),
                  'end' => _confirmEnd(context, party),
                  _ => null,
                },
                itemBuilder: (_) => [
                  if (env.setRadioEnabled != null)
                    CheckedPopupMenuItem(
                      value: 'radio',
                      checked: env.radioEnabled?.call() ?? false,
                      child: const Text('Radio quand la file est vide'),
                    ),
                  if (env.packPlaylists != null)
                    const PopupMenuItem(
                        value: 'pack', child: Text('Pack hors-ligne')),
                  const PopupMenuItem(
                      value: 'code', child: Text('Changer le code')),
                  const PopupMenuItem(
                      value: 'end', child: Text('Terminer la soirée')),
                ],
              ),
            ],
            bottom: TabBar(
              indicatorColor: partyAccent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: [
                Tab(text: 'File (${party.queue.items.length})'),
                Tab(text: 'Invités (${party.queue.guestCount})'),
              ],
            ),
          ),
          body: Column(
            children: [
              PartyStatusBanner(party: party),
              _CodeBar(party: party, onShowQr: () => _showQr(context, party)),
              Expanded(
                child: TabBarView(
                  children: [
                    _HostQueue(party: party),
                    _GuestList(party: party, guests: guests),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showQr(BuildContext context, PartyController party) {
    final relay = party.relayUrl, code = party.code;
    if (relay == null || code == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PartyQrScreen(
        invite: PartyInvite(relayUrl: relay, code: code),
        partyName: party.partyName,
      ),
    ));
  }

  static Future<void> _rotateCode(
      BuildContext context, PartyController party) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: partySurface,
        title: const Text('Changer le code ?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Les invités déjà là restent. L\'ancien code et l\'ancien QR ne '
          'marchent plus : pratique après avoir exclu quelqu\'un.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Changer')),
        ],
      ),
    );
    if (ok == true) party.rotateCode();
  }

  static Future<void> _confirmEnd(
      BuildContext context, PartyController party) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: partySurface,
        title: const Text('Terminer la soirée ?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Tous les invités sont déconnectés et la file est effacée. '
          'La musique en cours continue sur ton appareil.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Terminer')),
        ],
      ),
    );
    if (ok == true) await party.end();
  }
}

class _CodeBar extends StatelessWidget {
  const _CodeBar({required this.party, required this.onShowQr});

  final PartyController party;
  final VoidCallback onShowQr;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onShowQr,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: partySurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.qr_code_2, color: partyAccent, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Code de la soirée', style: partyMuted),
                  Text(
                    party.code ?? '…',
                    key: const ValueKey('party-code'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      letterSpacing: 4,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Text('Toucher pour\nle QR code',
                textAlign: TextAlign.right, style: partyMuted),
          ],
        ),
      ),
    );
  }
}

class _HostQueue extends StatelessWidget {
  const _HostQueue({required this.party});

  final PartyController party;

  @override
  Widget build(BuildContext context) {
    final items = party.queue.items;
    final env = context.read<PartyEnvironment>();
    return ListView(
      children: [
        PartyNowPlayingCard(song: party.nowPlaying),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Pas encore de proposition. Montre le QR code à tes invités : '
              'leurs titres passeront après celui en cours.',
              textAlign: TextAlign.center,
              style: partyMuted,
            ),
          ),
        for (final (index, item) in items.indexed)
          PartyQueueTile(
            item: item,
            position: index,
            votesEnabled: party.rules.votesEnabled,
            onPlayNow: () => env.playNow(item),
            onVeto: () => party.veto(item.id),
          ),
      ],
    );
  }
}

class _GuestList extends StatelessWidget {
  const _GuestList({required this.party, required this.guests});

  final PartyController party;
  final List<PartyGuest> guests;

  @override
  Widget build(BuildContext context) {
    final others = guests.where((g) => g.id != party.memberId).toList();
    if (others.isEmpty) {
      return const Center(
        child: Text('Personne pour le moment.', style: partyMuted),
      );
    }
    return ListView(
      children: [
        for (final guest in others)
          ListTile(
            key: ValueKey('party-guest-${guest.id}'),
            leading: Icon(Icons.circle,
                size: 12,
                color: guest.online ? Colors.greenAccent : Colors.white24),
            title:
                Text(guest.name, style: const TextStyle(color: Colors.white)),
            subtitle: Text(
              guest.pending == 0
                  ? 'Aucun titre en attente'
                  : '${guest.pending} en attente',
              style: partyMuted,
            ),
            trailing: IconButton(
              tooltip: 'Retirer ou exclure',
              icon: const Icon(Icons.person_remove, color: Colors.white54),
              onPressed: () => _kick(context, guest),
            ),
          ),
      ],
    );
  }

  Future<void> _kick(BuildContext context, PartyGuest guest) async {
    final ban = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: partySurface,
        title: Text('Retirer ${guest.name} ?',
            style: const TextStyle(color: Colors.white)),
        content: const Text(
          'Retirer : il peut revenir. Exclure : ses titres sont effacés et '
          'il ne peut plus revenir avec ce téléphone. Change aussi le code '
          's\'il le connaît.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Retirer')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Exclure',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ban != null) party.kick(guest.id, ban: ban);
  }
}
