import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/party_controller.dart';
import '../../services/party/party_models.dart';
import 'party_ambiance_screen.dart';
import 'party_widgets.dart';

/// Invite pendant la soiree : titre en cours et file (avec votes), et un
/// onglet pour chercher et proposer des titres.
class PartyGuestScreen extends StatelessWidget {
  const PartyGuestScreen({super.key});

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
                tooltip: 'Quitter la soirée',
                icon: const Icon(Icons.logout),
                onPressed: () => _confirmLeave(context, party),
              ),
            ],
            bottom: const TabBar(
              indicatorColor: partyAccent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: [Tab(text: 'La file'), Tab(text: 'Proposer')],
            ),
          ),
          body: Column(
            children: [
              PartyStatusBanner(party: party),
              Expanded(
                child: TabBarView(
                  children: [
                    _GuestQueue(party: party),
                    _SuggestTab(party: party),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _confirmLeave(
      BuildContext context, PartyController party) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: partySurface,
        title: const Text('Quitter la soirée ?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Tes titres restent dans la file. Pour revenir, rescanne le code.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Rester')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Quitter')),
        ],
      ),
    );
    if (ok == true) await party.leave();
  }
}

class _GuestQueue extends StatelessWidget {
  const _GuestQueue({required this.party});

  final PartyController party;

  @override
  Widget build(BuildContext context) {
    final items = party.queue.items;
    final mine = items.where((i) => i.mine).length;
    return ListView(
      children: [
        PartyNowPlayingCard(song: party.nowPlaying),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            items.isEmpty
                ? 'La file est vide : propose le prochain titre !'
                : 'À suivre · tes titres : $mine/${party.rules.maxPendingPerGuest}',
            style: partyMuted,
          ),
        ),
        for (final (index, item) in items.indexed)
          PartyQueueTile(
            item: item,
            position: index,
            votesEnabled: party.rules.votesEnabled,
            // Voter pour son propre titre n'a pas de sens.
            onVote: item.mine ? null : (value) => party.vote(item.id, value),
          ),
      ],
    );
  }
}

class _SuggestTab extends StatefulWidget {
  const _SuggestTab({required this.party});

  final PartyController party;

  @override
  State<_SuggestTab> createState() => _SuggestTabState();
}

class _SuggestTabState extends State<_SuggestTab> {
  final _query = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Le relais limite a une recherche par seconde : on attend que la
  /// frappe se calme.
  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(
        const Duration(milliseconds: 450), () => widget.party.search(text));
  }

  @override
  Widget build(BuildContext context) {
    final party = widget.party;
    final queued = {
      for (final item in party.queue.items) item.song.songId,
      if (party.nowPlaying != null) party.nowPlaying!.songId,
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            key: const ValueKey('party-search-field'),
            controller: _query,
            onChanged: _onChanged,
            onSubmitted: party.search,
            maxLength: 100,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Titre, artiste, album…',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: partySurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (party.searching) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(
            children: [
              if (!party.searching &&
                  party.searchResults.isEmpty &&
                  _query.text.trim().length >= 2)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Aucun résultat.',
                      textAlign: TextAlign.center, style: partyMuted),
                ),
              for (final song in party.searchResults)
                _ResultTile(
                  song: song,
                  alreadyQueued: queued.contains(song.songId),
                  onSuggest: () => party.suggest(song),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.song,
    required this.alreadyQueued,
    required this.onSuggest,
  });

  final PartySong song;
  final bool alreadyQueued;
  final VoidCallback onSuggest;

  @override
  Widget build(BuildContext context) => ListTile(
        key: ValueKey('party-result-${song.songId}'),
        leading: PartyCover(coverId: song.coverId),
        title: Text(song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          [song.artist, formatPartyDuration(song.durationMs)]
              .where((s) => s.isNotEmpty)
              .join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: partyMuted,
        ),
        trailing: alreadyQueued
            ? const Text('dans la file', style: partyMuted)
            : IconButton(
                tooltip: 'Proposer',
                icon: const Icon(Icons.add_circle, color: partyAccent),
                onPressed: onSuggest,
              ),
        onTap: alreadyQueued ? null : onSuggest,
      );
}
