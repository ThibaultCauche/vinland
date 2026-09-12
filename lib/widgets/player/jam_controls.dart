import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';

/// Menu Jam partage entre mobile (player_options_sheet.dart) et desktop
/// (desktop_player_bar.dart) : demarrer/rejoindre/quitter une session
/// d'ecoute synchronisee (voir AppState.startJamSession et
/// lib/services/jam_service.dart).
void showJamMenu(BuildContext context) {
  final state = context.read<AppState>();
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.isJamActive)
            ListTile(
              leading: const Icon(Icons.close, color: Colors.white, size: 26),
              title: Text(
                state.isJamHost
                    ? 'Quitter la session Jam (${state.jamParticipantCount} a l\'ecoute)'
                    : 'Quitter la session Jam',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              onTap: () {
                Navigator.pop(ctx);
                state.leaveJamSession();
              },
              minLeadingWidth: 24,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.groups, color: Colors.white, size: 26),
              title: const Text('Demarrer une session Jam',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              onTap: () {
                Navigator.pop(ctx);
                _startJam(context);
              },
              minLeadingWidth: 24,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            ListTile(
              leading:
                  const Icon(Icons.group_add, color: Colors.white, size: 26),
              title: const Text('Rejoindre une session Jam',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              onTap: () {
                Navigator.pop(ctx);
                _showJoinJamDialog(context);
              },
              minLeadingWidth: 24,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> _startJam(BuildContext context) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final sessionId = await state.startJamSession();
  if (sessionId == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Impossible de joindre le relais Jam'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }
  if (!context.mounted) return;
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Session Jam demarree !',
          style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Partage ce code a tes amis pour qu\'ils rejoignent ton ecoute :',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          SelectableText(
            sessionId,
            style: const TextStyle(
              color: Color(0xFF1DB954),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: sessionId));
            Navigator.pop(context);
          },
          child: const Text('Copier et fermer',
              style: TextStyle(color: Color(0xFF1DB954))),
        ),
      ],
    ),
  );
}

void _showJoinJamDialog(BuildContext context) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Rejoindre une session Jam',
          style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Code partage par ton ami',
          hintStyle: TextStyle(color: Colors.white38),
          border: UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF2A2A2A)),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () async {
            final code = controller.text.trim();
            if (code.isEmpty) return;
            final navigator = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            final ok = await context.read<AppState>().joinJamSession(code);
            navigator.pop();
            messenger.showSnackBar(
              SnackBar(
                content: Text(ok
                    ? 'Session rejointe !'
                    : 'Code invalide ou relais injoignable'),
                backgroundColor: ok ? const Color(0xFF2A2A2A) : Colors.red,
              ),
            );
          },
          child: const Text('Rejoindre',
              style: TextStyle(color: Color(0xFF1DB954))),
        ),
      ],
    ),
  );
}
