import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/party/party_link.dart';

/// QR code plein ecran, fond blanc pour qu'il se scanne meme dans une piece
/// sombre. Le code s'affiche aussi en gros pour ceux qui le tapent.
class PartyQrScreen extends StatelessWidget {
  const PartyQrScreen({
    super.key,
    required this.invite,
    required this.partyName,
  });

  final PartyInvite invite;
  final String partyName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: Text(partyName.isEmpty ? 'Soirée' : partyName),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final side = (box.biggest.shortestSide - 48).clamp(160.0, 520.0);
            return Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QrImageView(
                      data: invite.toString(),
                      size: side,
                      backgroundColor: Colors.white,
                      // Niveau M : se lit encore avec un ecran un peu sale ou
                      // un reflet, sans grossir les modules.
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                    const SizedBox(height: 16),
                    const Text('Scanne avec Vinland, ou tape le code :',
                        style: TextStyle(color: Colors.black54, fontSize: 15)),
                    const SizedBox(height: 4),
                    SelectableText(
                      invite.code,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 40,
                        letterSpacing: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
