import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

/// Une Chromecast (ou enceinte/tele compatible Cast) trouvee sur le Wi-Fi.
@immutable
class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    required this.host,
    this.port = 8009,
    this.model,
  });

  /// Nom de service mDNS : stable tant que l'appareil ne change pas.
  final String id;

  /// Nom choisi dans Google Home (« Salon »).
  final String name;
  final String host;
  final int port;

  /// Modele (« Chromecast », « Google Nest Mini »...), si annonce.
  final String? model;

  /// Une enceinte sans ecran (groupe, Nest Audio...) : affichee avec une
  /// autre icone.
  bool get isSpeaker {
    final m = model?.toLowerCase() ?? '';
    return m.contains('nest') && !m.contains('hub') ||
        m.contains('home') ||
        m.contains('audio') ||
        m.contains('group');
  }

  /// Lit l'annonce mDNS `_googlecast._tcp` : nom dans `fn`, modele dans
  /// `md`. Null sans adresse utilisable.
  static CastDevice? fromService({
    required String serviceName,
    required List<String> addresses,
    required int port,
    required Map<String, String> attributes,
  }) {
    // IPv4 de preference : une adresse IPv6 de lien local (fe80::)
    // demande l'interface en plus pour etre jointe.
    String? host;
    for (final a in addresses) {
      final ip = InternetAddress.tryParse(a);
      if (ip == null) continue;
      if (ip.type == InternetAddressType.IPv4) {
        host = a;
        break;
      }
      host ??= ip.isLinkLocal ? null : a;
    }
    if (host == null) return null;
    final name = attributes['fn'];
    return CastDevice(
      id: serviceName,
      name: name != null && name.isNotEmpty ? name : serviceName,
      host: host,
      port: port > 0 ? port : 8009,
      model: attributes['md'],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CastDevice &&
      other.id == id &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(id, host, port);
}

/// Cherche les Chromecast du reseau. Separe de CastController pour etre
/// remplace par un faux dans les tests.
abstract class CastScanner {
  /// La liste complete des appareils, a chaque changement.
  Stream<List<CastDevice>> scan();
  Future<void> stop();
}

/// Recherche mDNS par le systeme (NSD sur Android, DNS-SD sur Windows),
/// via bonsoir.
class BonsoirCastScanner implements CastScanner {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  StreamController<List<CastDevice>>? _out;
  final _devices = <String, CastDevice>{};

  @override
  Stream<List<CastDevice>> scan() {
    unawaited(stop());
    final out = StreamController<List<CastDevice>>.broadcast();
    _out = out;
    unawaited(_start(out));
    return out.stream;
  }

  Future<void> _start(StreamController<List<CastDevice>> out) async {
    try {
      final discovery = BonsoirDiscovery(type: '_googlecast._tcp');
      _discovery = discovery;
      await discovery.initialize();
      if (!identical(_out, out)) {
        // Recherche arretee (ou relancee) pendant l'initialisation.
        try {
          await discovery.stop();
        } catch (_) {}
        return;
      }
      _sub = discovery.eventStream?.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            event.service.resolve(discovery.serviceResolver);
          case BonsoirDiscoveryServiceResolvedEvent() ||
                BonsoirDiscoveryServiceUpdatedEvent():
            final s = event.service!;
            final device = CastDevice.fromService(
              serviceName: s.name,
              addresses: s.hostAddresses,
              port: s.port,
              attributes: s.attributes,
            );
            if (device == null) return;
            _devices[device.id] = device;
            _emit(out);
          case BonsoirDiscoveryServiceLostEvent():
            if (_devices.remove(event.service.name) != null) _emit(out);
          default:
            break;
        }
      });
      _emit(out);
      await discovery.start();
    } catch (e) {
      debugPrint('Recherche Chromecast impossible: $e');
      if (!out.isClosed) out.addError(e);
    }
  }

  void _emit(StreamController<List<CastDevice>> out) {
    if (out.isClosed) return;
    final list = _devices.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    out.add(list);
  }

  @override
  Future<void> stop() async {
    // Tout est detache avant le premier await : scan() relance une
    // recherche juste apres avoir appele stop().
    final discovery = _discovery;
    final sub = _sub;
    final out = _out;
    _discovery = null;
    _sub = null;
    _out = null;
    _devices.clear();
    await sub?.cancel();
    if (discovery != null && !discovery.isStopped) {
      try {
        await discovery.stop();
      } catch (_) {
        // Deja arretee par le systeme.
      }
    }
    await out?.close();
  }
}
