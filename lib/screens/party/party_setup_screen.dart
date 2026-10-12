import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/party_controller.dart';
import '../../controllers/party_environment.dart';
import '../../services/party/party_models.dart';
import 'party_host_screen.dart';
import 'party_widgets.dart';

/// Hote : nom de la soiree et reglages, puis « Lancer la soirée ». Les
/// reglages sont fixes pour toute la soiree (le relais les borne).
class PartySetupScreen extends StatefulWidget {
  const PartySetupScreen({super.key});

  @override
  State<PartySetupScreen> createState() => _PartySetupScreenState();
}

class _PartySetupScreenState extends State<PartySetupScreen> {
  final _name = TextEditingController(text: 'Soirée');
  int _maxPending = 3;
  bool _votes = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _launch() async {
    final env = context.read<PartyEnvironment>();
    final party = context.read<PartyController>();
    final relay = env.relayUrl();
    final auth = env.hostAuth();
    if (relay == null || auth == null) {
      setState(() => _error =
          'Connecte-toi d\'abord à ton serveur pour lancer une soirée.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await party.create(
      relayUrl: relay,
      partyName: _name.text.trim().isEmpty ? 'Soirée' : _name.text.trim(),
      hostName: env.userName() ?? 'Hôte',
      auth: auth,
      rules: PartyRules(maxPendingPerGuest: _maxPending, votesEnabled: _votes),
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = party.error ?? 'Impossible de lancer la soirée.';
      });
      return;
    }
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PartyHostScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: partyBackground,
      appBar: partyAppBar('Lancer une soirée'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            maxLength: 40,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Nom de la soirée',
              labelStyle: TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 8),
          Text('Titres en attente par invité : $_maxPending',
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          Slider(
            key: const ValueKey('party-max-pending'),
            value: _maxPending.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: '$_maxPending',
            onChanged: (v) => setState(() => _maxPending = v.round()),
          ),
          const Text(
            'Chacun son tour : la file alterne entre les invités, '
            'et un invité ne peut pas proposer plus que ça d\'un coup.',
            style: partyMuted,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _votes,
            onChanged: (v) => setState(() => _votes = v),
            title: const Text('Votes', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Les invités votent pour départager les titres d\'un même tour.',
              style: partyMuted,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ta musique passe sur cet appareil : branche-le à l\'enceinte. '
            'Les invités proposent, tu gardes le veto.',
            style: partyMuted,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _launch,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.nightlife),
            label: const Text('Lancer la soirée'),
          ),
        ],
      ),
    );
  }
}
