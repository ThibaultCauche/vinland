import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../widgets/smooth_scroll.dart';
import '../widgets/cover_image.dart';
import 'glass.dart';

enum _LibrarySection { playlists, albums }

/// Bibliotheque desktop : grille de playlists/albums dans des cartes en
/// verre. L'import de fichiers locaux a son propre onglet dans la sidebar
/// (voir DesktopImportView) -- avant ici sous forme de petit bouton, jugé
/// difficile a trouver (retour utilisateur).
class DesktopLibraryView extends StatefulWidget {
  final ValueChanged<Playlist> onOpenPlaylist;
  final ValueChanged<Album> onOpenAlbum;

  const DesktopLibraryView({
    super.key,
    required this.onOpenPlaylist,
    required this.onOpenAlbum,
  });

  @override
  State<DesktopLibraryView> createState() => _DesktopLibraryViewState();
}

class _DesktopLibraryViewState extends State<DesktopLibraryView> {
  _LibrarySection _section = _LibrarySection.playlists;
  final _scrollController = SmoothScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, (List<Playlist>, List<Album>)>(
      selector: (_, state) => (state.playlists, state.likedAlbums),
      builder: (context, data, __) {
        final (playlists, albums) = data;

        // top: DesktopGlass.topInset -- meme raison que DesktopSearchView :
        // le titre fixe de cette page doit demarrer sous la TopBar flottante
        // du shell plutot que de s'y superposer.
        return Padding(
          padding: const EdgeInsets.only(top: DesktopGlass.topInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bibliotheque',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  _SegmentButton(
                    label: 'Playlists (${playlists.length})',
                    active: _section == _LibrarySection.playlists,
                    onTap: () =>
                        setState(() => _section = _LibrarySection.playlists),
                  ),
                  const SizedBox(width: 8),
                  _SegmentButton(
                    label: 'Albums (${albums.length})',
                    active: _section == _LibrarySection.albums,
                    onTap: () =>
                        setState(() => _section = _LibrarySection.albums),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _section == _LibrarySection.playlists
                    ? _grid(
                        count: playlists.length,
                        builder: (i) {
                          final pl = playlists[i];
                          return _GridTile(
                            title: pl.name,
                            subtitle: '${pl.trackIds.length} titre(s)',
                            coverPath: null,
                            icon: Icons.queue_music,
                            onTap: () => widget.onOpenPlaylist(pl),
                          );
                        },
                        empty: 'Aucune playlist',
                      )
                    : _grid(
                        count: albums.length,
                        builder: (i) {
                          final album = albums[i];
                          return _GridTile(
                            title: album.title,
                            subtitle: album.artist,
                            coverPath: album.coverPath,
                            icon: Icons.album,
                            onTap: () => widget.onOpenAlbum(album),
                          );
                        },
                        empty: 'Aucun album like',
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _grid({
    required int count,
    required Widget Function(int) builder,
    required String empty,
  }) {
    if (count == 0) {
      return Center(
          child: Text(empty, style: const TextStyle(color: Colors.white38)));
    }
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: DesktopGlass.playerBarReserve),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: count,
      itemBuilder: (context, i) => builder(i),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SegmentButton(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? Colors.white.withOpacity(0.16)
          : Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(label,
              style: TextStyle(
                  color: active ? Colors.white : Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? coverPath;
  final IconData icon;
  final VoidCallback onTap;

  const _GridTile({
    required this.title,
    required this.subtitle,
    required this.coverPath,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final exists = context.read<AppState>().coverExists(path);

    return DesktopHoverable(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double side =
                    constraints.maxWidth.isFinite ? constraints.maxWidth : 200;
                return Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
                    image: exists && path != null
                        ? DecorationImage(
                            image: coverImageProvider(context,
                                path: path, width: side, height: side),
                            fit: BoxFit.cover,
                            onError: (_, __) {},
                          )
                        : null,
                  ),
                  child: !exists
                      ? Icon(icon, color: Colors.white54, size: 40)
                      : null,
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}
