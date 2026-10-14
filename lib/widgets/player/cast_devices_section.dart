import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/cast_controller.dart';

const _green = Color(0xFF1DB954);

/// Partie « Diffuser sur » du menu Peripheriques : la liste des Chromecast
/// du Wi-Fi, cherchees tant que le menu est ouvert.
class CastDevicesSection extends StatefulWidget {
  const CastDevicesSection({super.key, required this.cast});

  final CastController cast;

  @override
  State<CastDevicesSection> createState() => _CastDevicesSectionState();
}

class _CastDevicesSectionState extends State<CastDevicesSection> {
  Timer? _slowScan;
  bool _scanLooksEmpty = false;

  @override
  void initState() {
    super.initState();
    // Apres l'image : startScan previent les autres ecouteurs (bouton
    // Peripheriques), interdit pendant la construction du menu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.cast.startScan();
    });
    _slowScan = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _scanLooksEmpty = true);
    });
  }

  @override
  void dispose() {
    _slowScan?.cancel();
    unawaited(widget.cast.stopScan());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cast = widget.cast;
    return ListenableBuilder(
      listenable: cast,
      builder: (context, _) {
        final devices = [
          ...cast.devices,
          // Encore affichee si l'annonce mDNS se perd pendant la diffusion.
          if (cast.device != null && !cast.devices.contains(cast.device))
            cast.device!,
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                'Diffuser sur',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
            _tile(
              icon: Icons.phone_android,
              title: 'Cet appareil',
              selected: !cast.isCasting,
              onTap: cast.isCasting ? cast.disconnect : null,
            ),
            for (final device in devices)
              _tile(
                icon: device.isSpeaker ? Icons.speaker : Icons.tv,
                title: device.name,
                subtitle: device.model,
                selected: cast.device == device,
                busy: cast.connecting == device,
                onTap: cast.device == device || cast.connecting != null
                    ? null
                    : () => cast.connect(device),
              ),
            if (devices.isEmpty)
              ListTile(
                leading: _scanLooksEmpty
                    ? const Icon(Icons.cast, color: Colors.white38, size: 26)
                    : const SizedBox(
                        width: 26,
                        height: 26,
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                title: Text(
                  _scanLooksEmpty
                      ? 'Aucune Chromecast trouvée'
                      : 'Recherche des Chromecast…',
                  style: const TextStyle(color: Colors.white38, fontSize: 16),
                ),
                subtitle: _scanLooksEmpty
                    ? const Text(
                        'Elle doit être sur le même Wi-Fi que cet appareil.',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      )
                    : null,
                minLeadingWidth: 24,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            if (cast.isCasting)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.volume_up,
                        color: Colors.white54, size: 22),
                    Expanded(
                      child: Slider(
                        value: cast.volume.clamp(0.0, 1.0),
                        activeColor: _green,
                        inactiveColor: Colors.white24,
                        onChanged: cast.setVolume,
                      ),
                    ),
                  ],
                ),
              ),
            if (cast.message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  cast.message!,
                  style:
                      const TextStyle(color: Colors.orangeAccent, fontSize: 13),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool selected,
    bool busy = false,
    VoidCallback? onTap,
  }) {
    final color = selected ? _green : Colors.white;
    return ListTile(
      leading: Icon(icon, color: color, size: 26),
      title: Text(title, style: TextStyle(color: color, fontSize: 16)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _green),
            )
          : selected
              ? const Icon(Icons.check, color: _green)
              : null,
      onTap: onTap,
      minLeadingWidth: 24,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }
}

/// Icone du bouton Peripheriques : Chromecast connectee, autre appareil
/// connecte, ou rien.
IconData deviceMenuIcon(CastController cast) =>
    cast.isCasting ? Icons.cast_connected : Icons.devices;

/// Infobulle du bouton Peripheriques.
String deviceMenuTooltip(CastController cast) {
  final device = cast.device;
  return device == null ? 'Périphériques' : 'Lecture sur ${device.name}';
}
