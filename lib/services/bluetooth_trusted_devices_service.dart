import 'package:flutter/services.dart';

class BluetoothDeviceInfo {
  final String name;
  final String address;
  const BluetoothDeviceInfo({required this.name, required this.address});
}

/// Cote Dart du pont natif Android pour la reprise auto au Bluetooth : liste
/// les appareils appaires et lit/ecrit la liste "de confiance" (stockee
/// nativement, relue par BluetoothConnectReceiver sans passer par Dart).
class BluetoothTrustedDevicesService {
  static const _channel = MethodChannel('vinland/bluetooth_devices');

  Future<List<BluetoothDeviceInfo>> getBondedDevices() async {
    final result =
        await _channel.invokeMethod<List<dynamic>>('getBondedDevices') ?? [];
    return result
        .map((e) => BluetoothDeviceInfo(
              name: (e as Map)['name'] as String,
              address: e['address'] as String,
            ))
        .toList();
  }

  Future<Set<String>> getTrustedAddresses() async {
    final result =
        await _channel.invokeMethod<List<dynamic>>('getTrustedDevices') ?? [];
    return result.cast<String>().toSet();
  }

  Future<void> setTrustedAddresses(Set<String> addresses) async {
    await _channel.invokeMethod('setTrustedDevices', addresses.toList());
  }

  /// Appele par BluetoothConnectReceiver (cote natif) quand un appareil de
  /// confiance se connecte alors que l'app tourne deja -- dans ce cas le
  /// receiver ne demarre pas de FlutterEngine headless, donc c'est le seul
  /// moyen de declencher la reprise de lecture.
  void onTrustedDeviceConnected(void Function() callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'trustedDeviceConnected') callback();
    });
  }
}
