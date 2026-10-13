import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/party/party_link.dart';

/// Scanne le QR code de l'hote et renvoie l'invitation (pop). Un QR qui
/// n'est pas une invitation Vinland est ignore, avec un message une seule
/// fois pour ne pas clignoter tant qu'il reste devant la camera.
class PartyScanScreen extends StatefulWidget {
  const PartyScanScreen({super.key});

  @override
  State<PartyScanScreen> createState() => _PartyScanScreenState();
}

class _PartyScanScreenState extends State<PartyScanScreen> {
  final _controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _lastRejected;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final invite = PartyInvite.tryParse(raw);
      if (invite != null) {
        _done = true;
        Navigator.of(context).pop(invite);
        return;
      }
      if (raw != _lastRejected) {
        _lastRejected = raw;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Ce QR code n'est pas une soirée Vinland."),
          backgroundColor: Color(0xFF2A2A2A),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scanner le QR code'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? "Vinland n'a pas accès à la caméra. Autorise-la dans "
                          "les réglages du téléphone, ou tape le code."
                      : 'Caméra indisponible. Tape le code à la place.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ),
          // Cadre de visee.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
