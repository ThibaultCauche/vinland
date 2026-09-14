import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/playlist.dart';
import '../screens/settings_screen.dart';
import '../widgets/cover_image.dart';
import '../widgets/sync_status_banner.dart';
import '../widgets/user_avatar.dart';
import 'glass.dart';

enum DesktopNavTab { home, search, library, friends, import_ }

/// Rail d'icones a gauche : nav principale en haut, puis raccourcis
/// (titres likes + playlists) sous forme de vignettes carrees defilantes,
/// comme la colonne de gauche de la reference.
class DesktopSidebar extends StatelessWidget {
  final DesktopNavTab activeTab;
  final ValueChanged<DesktopNavTab> onTabSelected;
  final ValueChanged<Playlist> onOpenPlaylist;
  final VoidCallback onOpenLikedSongs;

  const DesktopSidebar({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
    required this.onOpenPlaylist,
    required this.onOpenLikedSongs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      // top/bottom : la barre de titre et la barre de lecture flottent
      // desormais par-dessus la sidebar (voir desktop_app_shell.dart)
      // plutot que de reserver leur propre espace -- garde ces marges pour
      // ne pas demarrer/finir derriere elles.
      margin: const EdgeInsets.fromLTRB(12, DesktopGlass.titleBarHeight + 4, 6,
          DesktopGlass.playerBarReserve),
      child: GlassPanel(
        borderRadius: BorderRadius.circular(DesktopGlass.radiusLg),
        child: Column(
          children: [
            const SizedBox(height: 16),
            const Image(
              image: AssetImage('assets/icon/app_icon_foreground.png'),
              width: 32,
              height: 32,
            ),
            const SizedBox(height: 10),
            // Synchro NAS : discret ici, ne pousse rien quand elle n'est pas
            // active (SyncIndicator se replie a taille nulle), et vit dans
            // la sidebar plutot que dans le TopBar flottant pour rester
            // visible meme sur les vues poussees ou celui-ci se cache
            // (playlist/album/artiste).
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 2),
              child: SyncIndicator(size: 16),
            ),
            const SizedBox(height: 10),
            GlassIconButton(
              icon: Icons.home_rounded,
              active: activeTab == DesktopNavTab.home,
              tooltip: 'Accueil',
              onPressed: () => onTabSelected(DesktopNavTab.home),
            ),
            const SizedBox(height: 6),
            GlassIconButton(
              icon: Icons.search_rounded,
              active: activeTab == DesktopNavTab.search,
              tooltip: 'Recherche',
              onPressed: () => onTabSelected(DesktopNavTab.search),
            ),
            const SizedBox(height: 6),
            GlassIconButton(
              icon: Icons.headphones_rounded,
              active: activeTab == DesktopNavTab.library,
              tooltip: 'Bibliotheque',
              onPressed: () => onTabSelected(DesktopNavTab.library),
            ),
            const SizedBox(height: 6),
            GlassIconButton(
              icon: Icons.people_alt_rounded,
              active: activeTab == DesktopNavTab.friends,
              tooltip: 'Amis',
              onPressed: () => onTabSelected(DesktopNavTab.friends),
            ),
            const SizedBox(height: 6),
            GlassIconButton(
              icon: Icons.upload_rounded,
              active: activeTab == DesktopNavTab.import_,
              tooltip: 'Importer des fichiers',
              onPressed: () => onTabSelected(DesktopNavTab.import_),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: Colors.white.withOpacity(0.12), height: 1),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Selector<AppState, List<Playlist>>(
                selector: (_, state) => state.playlists,
                builder: (context, playlists, __) {
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _LikedSongsShortcut(onTap: onOpenLikedSongs),
                      const SizedBox(height: 10),
                      for (final pl in playlists) ...[
                        _PlaylistShortcut(
                            playlist: pl, onTap: () => onOpenPlaylist(pl)),
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: Colors.white.withOpacity(0.12), height: 1),
            ),
            const SizedBox(height: 12),
            // Avatar de profil deplace ici (bas de la sidebar) depuis le
            // TopBar flottant : il y occupait en permanence de la place en
            // haut de l'ecran meme sur les vues sans TopBar visible
            // (playlist/album/artiste), creant un grand vide au-dessus de
            // leur bloc titre/cover (retour testeurs).
            const _ProfileAvatarButton(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ProfileAvatarButton extends StatelessWidget {
  const _ProfileAvatarButton();

  void _showProfileMenu(BuildContext context) {
    final state = context.read<AppState>();
    final navigator = Navigator.of(context, rootNavigator: true);

    // Position ancree sur ce bouton (pas de coordonnees fixes) : le menu
    // doit s'ouvrir juste a cote de l'avatar quel que soit l'endroit ou il
    // se trouve, ici en bas de la sidebar plutot qu'en haut a droite comme
    // avant son demenagement.
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        navigator.overlay!.context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      color: const Color(0xFF1E1E1E),
      items: [
        PopupMenuItem(
          child:
              const Text('Parametres', style: TextStyle(color: Colors.white)),
          onTap: () {
            Future.microtask(() => navigator.push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ));
          },
        ),
        PopupMenuItem(
          child: const Text('Se deconnecter',
              style: TextStyle(color: Colors.white)),
          onTap: () => state.logout(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (String?, int)>(
      selector: (_, state) => (state.userName, state.avatarVersion),
      builder: (context, data, __) {
        final (userName, avatarVersion) = data;
        return Tooltip(
          message: 'Profil',
          child: DesktopHoverable(
            onTap: () => _showProfileMenu(context),
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: UserAvatar(
                username: userName ?? 'U',
                size: 36,
                cacheBust: avatarVersion,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LikedSongsShortcut extends StatelessWidget {
  final VoidCallback onTap;
  const _LikedSongsShortcut({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Titres likes',
      child: DesktopHoverable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF7B5CFA), Color(0xFF3E2CA8)],
              ),
            ),
            child: const Icon(Icons.favorite, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

class _PlaylistShortcut extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  const _PlaylistShortcut({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final firstTrackCover = playlist.trackIds.isNotEmpty
        ? state.allTracks
            .where((t) => t.id == playlist.trackIds.first)
            .map((t) => t.coverPath)
            .firstOrNull
        : null;
    final exists = state.coverExists(firstTrackCover);

    return Tooltip(
      message: playlist.name,
      child: DesktopHoverable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF3E3E3E),
              borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
              image: exists && firstTrackCover != null
                  ? DecorationImage(
                      image: coverImageProvider(context,
                          path: firstTrackCover, width: 44, height: 44),
                      fit: BoxFit.cover,
                      onError: (_, __) {},
                    )
                  : null,
            ),
            child: !exists
                ? const Icon(Icons.queue_music, color: Colors.white54, size: 18)
                : null,
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
