import 'package:flutter/material.dart';

import '../controllers/jam_controller.dart';
import '../domain/jam_sync.dart';

/// Ecran cache (appui long sur « Décalage audio » dans le menu Jam) : ecart
/// mesure avec l'hote a chaque battement et ce que l'app en a fait. Sert a
/// verifier en soiree, chiffres a l'appui, que deux appareils restent
/// alignes, et a choisir le decalage Bluetooth.
class JamSyncDebugScreen extends StatelessWidget {
  const JamSyncDebugScreen({super.key, required this.jam});

  final JamController jam;

  static const _muted = TextStyle(color: Colors.white54, fontSize: 13);
  static const _mono = TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontFeatures: [FontFeature.tabularFigures()]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
        title: const Text('Mesure de la synchro'),
        actions: [
          IconButton(
            tooltip: 'Effacer',
            icon: const Icon(Icons.delete_outline),
            onPressed: jam.clearSyncLog,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: jam,
        builder: (context, _) {
          final entries = jam.syncLog.entries.reversed.toList();
          final clock = jam.clock;
          final average = jam.syncLog.averageAbsDriftMs();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      average == null
                          ? 'Aucune mesure : rejoins un Jam en cours.'
                          : 'Écart moyen (30 dernières) : '
                              '${average.round()} ms',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      clock.isKnown
                          ? 'Horloge du relais : ${_signed(clock.offsetMs)} ms, '
                              'aller-retour ${clock.roundTripMs} ms'
                          : 'Horloge du relais : non mesurée (relais à mettre '
                              'à jour)',
                      style: _muted,
                    ),
                    Text(
                      'Décalage audio : '
                      '${_signed(jam.syncSettings.offset.inMilliseconds)} ms'
                      ' · vitesse ${(jam.currentSpeed * 100).toStringAsFixed(1)} %',
                      style: _muted,
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _row(entries[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(SyncLogEntry e) {
    final t = e.at;
    final time = '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(time, style: _muted)),
          SizedBox(
            width: 80,
            child: Text('${_signed(e.driftMs)} ms', style: _mono),
          ),
          Expanded(child: Text(e.actionLabel, style: _muted)),
        ],
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _signed(int n) => n > 0 ? '+$n' : '$n';
}
