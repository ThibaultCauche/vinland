import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navigation/overlay_navigator.dart';
import '../providers/app_state.dart';
import '../widgets/bottom_bar_reserve.dart';
import '../widgets/wrapped_view.dart';

/// Bilan d'ecoute en plein ecran (mobile), ouvert depuis l'accueil.
class WrappedScreen extends StatelessWidget implements SingleInstanceOverlay {
  const WrappedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.read<AppState>().popOverlay(),
        ),
        title: const Text('Ton bilan musical',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: WrappedView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomBarReserve(context)),
      ),
    );
  }
}
