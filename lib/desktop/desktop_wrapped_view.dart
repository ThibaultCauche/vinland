import 'package:flutter/material.dart';

import '../widgets/wrapped_view.dart';
import 'glass.dart';

/// Bilan d'ecoute sur PC, pousse depuis l'accueil.
class DesktopWrappedView extends StatelessWidget {
  const DesktopWrappedView({super.key});

  @override
  Widget build(BuildContext context) {
    // topInsetCompact : vue poussee, sans barre de recherche (voir
    // DesktopSeeAllView).
    return Padding(
      padding: const EdgeInsets.only(
          top: DesktopGlass.topInsetCompact, left: 24, right: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ton bilan musical',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: const WrappedView(
                  padding:
                      EdgeInsets.only(bottom: DesktopGlass.playerBarReserve),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
