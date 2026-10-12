import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/party_controller.dart';
import '../../controllers/party_environment.dart';
import '../../services/party/party_models.dart';
import '../../services/party/party_socket.dart';
import 'party_guest_screen.dart';
import 'party_host_screen.dart';
import 'party_join_screen.dart';
import 'party_offline_pack_screen.dart';
import 'party_setup_screen.dart';
import 'party_widgets.dart';

/// Ouvre le mode Soiree depuis le menu Jam : l'ecran de la soiree en cours
/// s'il y en a une, sinon le choix lancer / rejoindre.
void openPartyMode(NavigatorState navigator, PartyController party) {
  final Widget screen;
  if (party.isActive) {
    screen = party.isHost ? const PartyHostScreen() : const PartyGuestScreen();
  } else {
    screen = const PartyHomeScreen();
  }
  navigator.push(MaterialPageRoute(builder: (_) => screen));
}

class PartyHomeScreen extends StatefulWidget {
  const PartyHomeScreen({super.key});

  @override
  State<PartyHomeScreen> createState() => _PartyHomeScreenState();
}

class _PartyHomeScreenState extends State<PartyHomeScreen> {
  PartySeat? _seat;
  bool _resuming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    context.read<PartyController>().savedSeat().then((seat) {
      if (mounted) setState(() => _seat = seat);
    });
  }

  Future<void> _resume() async {
    final party = context.read<PartyController>();
    setState(() {
      _resuming = true;
      _error = null;
    });
    final ok = await party.resume();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _resuming = false;
        _seat = null;
        _error = party.error ?? 'Cette soirée n\'existe plus.';
      });
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) =>
          party.isHost ? const PartyHostScreen() : const PartyGuestScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final seat = _seat;
    return Scaffold(
      backgroundColor: partyBackground,
      appBar: partyAppBar('Mode soirée'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Une enceinte, un hôte, et tous les invités qui proposent des '
            'titres depuis leur téléphone. Chacun son tour, l\'hôte garde '
            'le dernier mot.',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 24),
          if (seat != null) ...[
            _BigChoice(
              icon: Icons.replay,
              title: seat.partyName.isEmpty
                  ? 'Revenir à la soirée'
                  : 'Revenir à « ${seat.partyName} »',
              subtitle: seat.role == PartyRole.host
                  ? 'Tu es l\'hôte de cette soirée'
                  : 'Ta place est gardée',
              onTap: _resuming ? null : _resume,
            ),
            const SizedBox(height: 12),
          ],
          _BigChoice(
            icon: Icons.nightlife,
            title: 'Lancer une soirée',
            subtitle: 'La musique passe sur cet appareil',
            onTap: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const PartySetupScreen())),
          ),
          const SizedBox(height: 12),
          _BigChoice(
            icon: Icons.qr_code_scanner,
            title: 'Rejoindre une soirée',
            subtitle: 'Avec le QR code ou le code de l\'hôte',
            onTap: () =>
                Navigator.of(context).pushReplacement(PartyJoinScreen.route()),
          ),
          if (context.read<PartyEnvironment>().packPlaylists != null) ...[
            const SizedBox(height: 12),
            _BigChoice(
              icon: Icons.offline_pin,
              title: 'Préparer un pack hors-ligne',
              subtitle: 'Télécharger une playlist avant la soirée',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const PartyOfflinePackScreen())),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
        ],
      ),
    );
  }
}

class _BigChoice extends StatelessWidget {
  const _BigChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: partySurface,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(icon, color: partyAccent, size: 32),
          title: Text(title,
              style: const TextStyle(color: Colors.white, fontSize: 17)),
          subtitle: Text(subtitle, style: partyMuted),
          onTap: onTap,
        ),
      );
}
