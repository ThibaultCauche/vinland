import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import '../../controllers/jam_sync_settings.dart';
import '../../controllers/party_controller.dart';
import '../../providers/app_state.dart';
import '../../screens/jam_sync_debug_screen.dart';
import '../../screens/party/party_home_screen.dart';

/// Menu Jam partage entre mobile (player_options_sheet.dart) et desktop
/// (desktop_player_bar.dart) : demarrer/rejoindre/quitter une session
/// d'ecoute synchronisee (voir AppState.startJamSession et
/// lib/services/jam_service.dart).
void showJamMenu(BuildContext context) {
  final state = context.read<AppState>();
  final transferTargets = state.jamTransferTargets;
  // Pris maintenant : la feuille d'options qui a ouvert ce menu peut etre
  // fermee (contexte demonte) au moment du tap.
  final navigator = Navigator.of(context);
  final party = context.read<PartyController>();
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
          if (state.isJamHost && transferTargets.isNotEmpty)
            for (final username in transferTargets)
              ListTile(
                leading:
                    const Icon(Icons.swap_horiz, color: Colors.white, size: 26),
                title: Text('Céder l\'hébergement à $username',
                    style: const TextStyle(color: Colors.white, fontSize: 16)),
                onTap: () {
                  Navigator.pop(ctx);
                  state.transferJamHost(username);
                },
                minLeadingWidth: 24,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
          if (state.isFriendJamActive)
            _JamOffsetTile(
              settings: state.jamSyncSettings,
              onOpenDebug: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => JamSyncDebugScreen(jam: state.jam),
                ));
              },
            ),
          if (state.isFriendJamActive)
            ListTile(
              leading: const Icon(Icons.close, color: Colors.white, size: 26),
              title: Text(
                state.isJamHost
                    ? 'Quitter la session Jam (${state.jamParticipantCount} à l\'écoute)'
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
              title: const Text('Démarrer une session Jam',
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
          // Mode Soiree : file partagee avec les invites, voir
          // docs/soiree-protocole.md.
          ListTile(
            leading: const Icon(Icons.nightlife, color: Colors.white, size: 26),
            title: const Text('Mode soirée',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            subtitle: const Text('Les invités proposent, tu gardes le veto',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            onTap: () {
              Navigator.pop(ctx);
              openPartyMode(navigator, party);
            },
            minLeadingWidth: 24,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Decalage audio de cet appareil pendant un Jam (casque ou enceinte
/// Bluetooth en retard sur les autres, voir JamSyncSettings), reglable a
/// l'oreille pendant l'ecoute : l'appareil se recale des qu'on lache le
/// curseur. Appui long : ecran cache de mesure (JamSyncDebugScreen).
class _JamOffsetTile extends StatelessWidget {
  const _JamOffsetTile({required this.settings, required this.onOpenDebug});

  final JamSyncSettings settings;
  final VoidCallback onOpenDebug;

  static String label(Duration offset) {
    final ms = offset.inMilliseconds;
    if (ms == 0) return 'Aucun';
    return ms > 0 ? '$ms ms en avance' : '${-ms} ms en retard';
  }

  @override
  Widget build(BuildContext context) {
    final max = JamSyncSettings.maxOffset.inMilliseconds;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.bluetooth_audio,
                color: Colors.white, size: 26),
            title: const Text('Décalage audio',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            subtitle: const Text(
                'Si ce téléphone sonne après les autres (Bluetooth), '
                'fais-le jouer en avance',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            trailing: Text(label(settings.offset),
                style: const TextStyle(color: Colors.white)),
            onLongPress: onOpenDebug,
            minLeadingWidth: 24,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          _OffsetSlider(settings: settings, max: max),
        ],
      ),
    );
  }
}

/// Curseur qui ne sauvegarde (et donc ne recale la lecture) qu'au
/// relachement : un recalage a chaque pixel ferait des dizaines de seeks.
class _OffsetSlider extends StatefulWidget {
  const _OffsetSlider({required this.settings, required this.max});

  final JamSyncSettings settings;
  final int max;

  @override
  State<_OffsetSlider> createState() => _OffsetSliderState();
}

class _OffsetSliderState extends State<_OffsetSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final current = widget.settings.offset.inMilliseconds.toDouble();
    final value = _dragging ?? current;
    final step = JamSyncSettings.step.inMilliseconds;
    return Slider(
      value: value,
      min: -widget.max.toDouble(),
      max: widget.max.toDouble(),
      divisions: 2 * widget.max ~/ step,
      label: _JamOffsetTile.label(Duration(milliseconds: value.round())),
      activeColor: const Color(0xFF1DB954),
      onChanged: (v) => setState(() => _dragging = v),
      onChangeEnd: (v) {
        setState(() => _dragging = null);
        widget.settings.setOffset(Duration(milliseconds: v.round()));
      },
    );
  }
}

/// Menu "Peripheriques" (Spotify Connect-like), partage mobile/desktop :
/// affiche l'autre appareil du meme compte en train d'ecouter (voir
/// AppState.isPersonalSyncParticipant) et propose d'y reprendre la lecture
/// ici (voir AppState.takeOverPersonalSync) -- ou, si CET appareil est
/// l'hote actuel (voir AppState.isPersonalSyncHost), confirme quel autre
/// appareil le pilote deja (voir connectedParticipantDeviceName) : sans ca,
/// l'hote n'avait aucun moyen de voir qu'un autre appareil avait bien
/// detecte sa lecture et la controlait deja (retour utilisateur).
void showDeviceMenu(BuildContext context) {
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
          if (state.isPersonalSyncParticipant && state.remoteTrack != null)
            ListTile(
              leading: const Icon(Icons.devices, color: Colors.white, size: 26),
              title: Text(
                'Reprendre ici (${state.remoteDeviceName ?? 'autre appareil'})',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              subtitle: Text(
                '${state.remoteTrack!.title} - ${state.remoteTrack!.artist}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              onTap: () {
                Navigator.pop(ctx);
                state.takeOverPersonalSync();
              },
              minLeadingWidth: 24,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            )
          else if (state.isPersonalSyncHost &&
              state.connectedParticipantDeviceName != null)
            ListTile(
              leading: const Icon(Icons.devices, color: Colors.white, size: 26),
              title: Text(
                'Connecté : ${state.connectedParticipantDeviceName}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              subtitle: const Text(
                'Peut déjà piloter la lecture ici',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              minLeadingWidth: 24,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            )
          else
            const ListTile(
              leading:
                  Icon(Icons.devices_other, color: Colors.white38, size: 26),
              title: Text('Aucun autre appareil connecté',
                  style: TextStyle(color: Colors.white38, fontSize: 16)),
              minLeadingWidth: 24,
              contentPadding: EdgeInsets.symmetric(horizontal: 20),
            ),
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
      title: const Text('Session Jam démarrée !',
          style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Partage ce code à tes amis pour qu\'ils rejoignent ton écoute :',
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
          hintText: 'Code partagé par ton ami',
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
