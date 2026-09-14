import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class BottomNav extends StatelessWidget {
  const BottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    // FIX: Selector — on n'écoute QUE currentTab (+ le nombre de partages en
    // attente, pour le badge sur l'onglet Amis)
    return Selector<AppState, (int, int)>(
      selector: (_, state) => (state.currentTab, state.pendingShares.length),
      builder: (context, data, child) {
        final (currentTab, pendingCount) = data;
        return BottomNavigationBar(
          currentIndex: currentTab,
          onTap: (i) {
            final state = context.read<AppState>();
            if (state.overlayStack.isNotEmpty) state.clearOverlays();
            state.setTab(i);
          },
          backgroundColor: Colors.transparent,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white70,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          useLegacyColorScheme: false,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Accueil',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.library_music_outlined),
              activeIcon: Icon(Icons.library_music),
              label: 'Bibliothèque',
            ),
            BottomNavigationBarItem(
              icon: Badge(
                isLabelVisible: pendingCount > 0,
                label: Text('$pendingCount'),
                child: const Icon(Icons.people_outline),
              ),
              activeIcon: Badge(
                isLabelVisible: pendingCount > 0,
                label: Text('$pendingCount'),
                child: const Icon(Icons.people),
              ),
              label: 'Amis',
            ),
          ],
        );
      },
    );
  }
}
