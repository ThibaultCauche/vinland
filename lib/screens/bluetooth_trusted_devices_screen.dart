import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/bluetooth_trusted_devices_service.dart';
import '../widgets/app_background.dart';

/// Choix des appareils Bluetooth "de confiance" : quand un d'entre eux se
/// connecte, l'app reprend automatiquement la derniere lecture en fond, sans
/// avoir besoin d'etre ouverte au prealable (voir BluetoothConnectReceiver
/// cote Android -- fonctionnalite Android uniquement).
class BluetoothTrustedDevicesScreen extends StatefulWidget {
  const BluetoothTrustedDevicesScreen({super.key});

  @override
  State<BluetoothTrustedDevicesScreen> createState() =>
      _BluetoothTrustedDevicesScreenState();
}

class _BluetoothTrustedDevicesScreenState
    extends State<BluetoothTrustedDevicesScreen> {
  final _service = BluetoothTrustedDevicesService();
  bool _loading = true;
  bool _permissionDenied = false;
  List<BluetoothDeviceInfo> _devices = [];
  Set<String> _trusted = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final status = await Permission.bluetoothConnect.request();
    if (!status.isGranted) {
      setState(() {
        _loading = false;
        _permissionDenied = true;
      });
      return;
    }
    final devices = await _service.getBondedDevices();
    final trusted = await _service.getTrustedAddresses();
    setState(() {
      _devices = devices;
      _trusted = trusted;
      _loading = false;
      _permissionDenied = false;
    });
  }

  Future<void> _toggle(String address, bool value) async {
    setState(() {
      if (value) {
        _trusted.add(address);
      } else {
        _trusted.remove(address);
      }
    });
    await _service.setTrustedAddresses(_trusted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Reprise automatique',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: AppBackground(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF1DB954)))
            : _permissionDenied
                ? _PermissionDenied(onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        "Coche un ou plusieurs appareils appaires (casque, enceinte...) : "
                        "quand l'un d'eux se connecte, Vinland reprend automatiquement "
                        "la derniere lecture en fond, meme si l'app n'a jamais ete "
                        'ouverte depuis le dernier redemarrage du telephone.',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      if (_devices.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 32),
                          child: Center(
                            child: Text('Aucun appareil Bluetooth appaire',
                                style: TextStyle(color: Colors.white38)),
                          ),
                        )
                      else
                        ..._devices.map((d) => SwitchListTile(
                              secondary: const Icon(Icons.bluetooth,
                                  color: Colors.white54),
                              title: Text(d.name,
                                  style: const TextStyle(color: Colors.white)),
                              subtitle: Text(d.address,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 12)),
                              activeColor: const Color(0xFF1DB954),
                              value: _trusted.contains(d.address),
                              onChanged: (v) => _toggle(d.address, v),
                            )),
                    ],
                  ),
      ),
    );
  }
}

class _PermissionDenied extends StatelessWidget {
  final VoidCallback onRetry;
  const _PermissionDenied({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth_disabled,
                color: Colors.white24, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Permission Bluetooth requise pour lister les appareils appaires.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: const Text('Reessayer',
                  style: TextStyle(color: Color(0xFF1DB954))),
            ),
          ],
        ),
      ),
    );
  }
}
