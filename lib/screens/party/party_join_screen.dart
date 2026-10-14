import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/party_controller.dart';
import '../../controllers/party_environment.dart';
import '../../services/party/party_link.dart';
import 'party_guest_screen.dart';
import 'party_scan_screen.dart';
import 'party_widgets.dart';

/// Scanner seulement sur telephone : mobile_scanner n'a pas de version
/// Windows, on y tape le code.
bool get partyCanScan => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Invite : code (ou QR scanne) + pseudo, puis entree dans la soiree.
class PartyJoinScreen extends StatefulWidget {
  const PartyJoinScreen({super.key, this.invite, bool? canScan})
      : canScan = canScan ?? false;

  /// Invitation deja connue (lien vinland://soiree ouvert, QR scanne).
  final PartyInvite? invite;
  final bool canScan;

  /// Ouvre l'ecran avec le scanner disponible si l'appareil en a un.
  static Route<void> route({PartyInvite? invite}) => MaterialPageRoute(
        builder: (_) => PartyJoinScreen(invite: invite, canScan: partyCanScan),
      );

  @override
  State<PartyJoinScreen> createState() => _PartyJoinScreenState();
}

class _PartyJoinScreenState extends State<PartyJoinScreen> {
  static const _nameKey = 'vinland_party_guest_name';

  final _code = TextEditingController();
  final _name = TextEditingController();
  String? _relay;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final invite = widget.invite;
    if (invite != null) {
      _code.text = invite.code;
      _relay = invite.relayUrl;
    }
    _loadName();
  }

  Future<void> _loadName() async {
    final fromAccount = context.read<PartyEnvironment>().userName();
    String? saved;
    try {
      saved = (await SharedPreferences.getInstance()).getString(_nameKey);
    } catch (_) {}
    if (!mounted || _name.text.isNotEmpty) return;
    _name.text = saved ?? fromAccount ?? '';
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final invite = await Navigator.of(context).push<PartyInvite>(
        MaterialPageRoute(builder: (_) => const PartyScanScreen()));
    if (invite == null || !mounted) return;
    setState(() {
      _code.text = invite.code;
      _relay = invite.relayUrl;
      _error = null;
    });
    if (_name.text.trim().isNotEmpty) await _join();
  }

  Future<void> _join() async {
    final code = normalizePartyCode(_code.text);
    final name = _name.text.trim();
    if (code == null) {
      setState(
          () => _error = 'Le code fait 6 caractères (lettres et chiffres).');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Choisis un pseudo.');
      return;
    }
    // Code tape sans QR : meme relais que notre serveur (cercle d'amis sur
    // le meme NAS).
    final relay = _relay ?? context.read<PartyEnvironment>().relayUrl();
    if (relay == null) {
      setState(() => _error = 'Scanne le QR code de l\'hôte pour entrer.');
      return;
    }
    final party = context.read<PartyController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (await SharedPreferences.getInstance()).setString(_nameKey, name);
    } catch (_) {}
    final ok = await party.join(relayUrl: relay, code: code, name: name);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = party.error ?? 'Impossible d\'entrer dans la soirée.';
      });
      return;
    }
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PartyGuestScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return PartyBackground(
        child: Scaffold(
      backgroundColor: partyBackground,
      appBar: partyAppBar('Rejoindre une soirée'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.canScan) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scanner le QR code'),
            ),
            const SizedBox(height: 16),
            const Center(child: Text('ou', style: partyMuted)),
          ],
          TextField(
            key: const ValueKey('party-code-field'),
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            maxLength: 7,
            style: const TextStyle(
                color: Colors.white, fontSize: 22, letterSpacing: 4),
            decoration: const InputDecoration(
              labelText: 'Code de la soirée',
              labelStyle: TextStyle(color: Colors.white54),
            ),
          ),
          TextField(
            key: const ValueKey('party-name-field'),
            controller: _name,
            maxLength: 30,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Ton pseudo',
              labelStyle: TextStyle(color: Colors.white54),
            ),
            onSubmitted: (_) => _join(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _join,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Entrer'),
          ),
        ],
      ),
    ));
  }
}
