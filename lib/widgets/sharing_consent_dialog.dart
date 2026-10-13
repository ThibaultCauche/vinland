import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/sharing_consent.dart';

/// Pose une fois par compte la question « qu'est-ce que tes amis voient ? »
/// (voir SharingConsent) dès que la bibliothèque du compte est chargée.
/// Enveloppe le shell mobile comme le shell desktop.
class SharingConsentGate extends StatefulWidget {
  final Widget child;
  const SharingConsentGate({super.key, required this.child});

  @override
  State<SharingConsentGate> createState() => _SharingConsentGateState();
}

class _SharingConsentGateState extends State<SharingConsentGate> {
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    final needsConsent =
        context.select<AppState, bool>((s) => s.needsSharingConsent);
    if (needsConsent && !_dialogOpen) {
      _dialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
    }
    return widget.child;
  }

  Future<void> _ask() async {
    if (!mounted) return;
    final state = context.read<AppState>();
    final choice = await showSharingConsentDialog(
      context,
      initial: SharingConsent(
        likes: state.shareLikesWithFriends,
        recentPlays: state.shareRecentPlaysWithFriends,
        nowPlaying: state.shareNowPlayingWithFriends,
        asked: false,
      ),
    );
    if (choice != null) {
      unawaited(state.confirmSharingConsent(
        likes: choice.likes,
        recentPlays: choice.recentPlays,
        nowPlaying: choice.nowPlaying,
      ));
    }
    if (mounted) setState(() => _dialogOpen = false);
  }
}

/// Dialogue de consentement, pré-rempli avec [initial]. Ne se ferme qu'avec
/// le bouton « Valider » : le choix doit être explicite.
Future<SharingConsent?> showSharingConsentDialog(
  BuildContext context, {
  required SharingConsent initial,
}) {
  return showDialog<SharingConsent>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: _SharingConsentDialog(initial: initial),
    ),
  );
}

class _SharingConsentDialog extends StatefulWidget {
  final SharingConsent initial;
  const _SharingConsentDialog({required this.initial});

  @override
  State<_SharingConsentDialog> createState() => _SharingConsentDialogState();
}

class _SharingConsentDialogState extends State<_SharingConsentDialog> {
  late bool _likes = widget.initial.likes;
  late bool _recentPlays = widget.initial.recentPlays;
  late bool _nowPlaying = widget.initial.nowPlaying;

  static const _green = Color(0xFF1DB954);

  Widget _switch(
      String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      activeThumbColor: _green,
      value: value,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Ce que tes amis voient',
          style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Les autres comptes de ce serveur peuvent voir une partie de '
              'ton activité. Choisis ce que tu partages ; tu pourras le '
              'changer à tout moment dans Paramètres > Amis.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            _switch('Mes titres likés', 'Visibles sur ton profil', _likes,
                (v) => setState(() => _likes = v)),
            _switch('Mes écoutes récentes', 'Les derniers titres écoutés',
                _recentPlays, (v) => setState(() => _recentPlays = v)),
            _switch(
                'Ce que j\'écoute en ce moment',
                'Dans l\'onglet Amis, et pour rejoindre ton Jam en un tap',
                _nowPlaying,
                (v) => setState(() => _nowPlaying = v)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            SharingConsent(
              likes: _likes,
              recentPlays: _recentPlays,
              nowPlaying: _nowPlaying,
              asked: true,
            ),
          ),
          child: const Text('Valider', style: TextStyle(color: _green)),
        ),
      ],
    );
  }
}
