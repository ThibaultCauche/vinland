import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class BottomNav extends StatelessWidget {
  const BottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomSafePadding = MediaQuery.of(context).padding.bottom;

    return Consumer<AppState>(
      builder: (context, state, child) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF121212),
            border: Border(
              top: BorderSide(color: Color(0xFF282828), width: 0.5),
            ),
          ),
          // ← On ajoute le padding système ICI, pas dans BottomNavigationBar
          padding: EdgeInsets.only(bottom: bottomSafePadding),
          child: BottomNavigationBar(
            currentIndex: state.currentTab,
            onTap: (i) {
              if (state.overlayStack.isNotEmpty) {
                state.clearOverlays();
              }
              state.setTab(i);
            },
            backgroundColor:
                Colors.transparent, // ← Transparent car Container gère
            selectedItemColor: Colors.white,
            unselectedItemColor: Colors.white38,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            // ← Désactive le padding interne automatique
            useLegacyColorScheme: false,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Accueil',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.library_music_outlined),
                activeIcon: Icon(Icons.library_music),
                label: 'Bibliothèque',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.people_outline),
                activeIcon: Icon(Icons.people),
                label: 'Amis',
              ),
            ],
          ),
        );
      },
    );
  }
}
