import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/app_state.dart';
import '../widgets/cover_image.dart';
import 'glass.dart';

/// Ligne de titre façon reference : cover, titre/artiste(s), album, duree,
/// like puis menu, avec un survol legerement eclairci.
class DesktopTrackRow extends StatefulWidget {
  final Track track;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onMore;
  // Optionnels : sans eux la colonne album / les noms d'artiste restent de
  // simples textes non cliquables (cas des ecrans qui n'ont pas encore de
  // navigation album/artiste cablee vers cette ligne).
  final VoidCallback? onOpenAlbum;
  final void Function(String artistName)? onOpenArtist;

  const DesktopTrackRow({
    super.key,
    required this.track,
    required this.onTap,
    required this.onLike,
    required this.onMore,
    this.isPlaying = false,
    this.onOpenAlbum,
    this.onOpenArtist,
  });

  @override
  State<DesktopTrackRow> createState() => _DesktopTrackRowState();
}

class _DesktopTrackRowState extends State<DesktopTrackRow> {
  bool _hover = false;
  final _moreButtonKey = GlobalKey();

  /// Menu "..." ancre sur son propre bouton (via _moreButtonKey) : pour
  /// l'instant une seule entree, "Ajouter a la file d'attente" -- ce bouton
  /// ne faisait jusqu'ici absolument rien sur desktop (onMore etait un
  /// no-op partout ou cette ligne est reutilisee : Titres likes, playlists,
  /// albums, artistes, recherche).
  void _showMoreMenu() {
    final box = _moreButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + box.size.height,
      overlay.size.width - topLeft.dx - box.size.width,
      0,
    );
    showMenu<void>(
      context: context,
      position: position,
      color: const Color(0xFF1E1E1E),
      items: [
        PopupMenuItem<void>(
          child: const Row(
            children: [
              Icon(Icons.queue_music, color: Colors.white70, size: 18),
              SizedBox(width: 10),
              Text('Ajouter a la file d\'attente',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
          onTap: () => context.read<AppState>().addToQueue(widget.track),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final path = track.coverPath;
    // Titre importe via CSV mais introuvable sur le NAS (voir
    // AppState.likedTracksWithMissing) : pas de fichier reel, donc grise,
    // non cliquable, sans bouton like/menu (rien a jouer ni a liker).
    final isPlaceholder = track.isPlaceholder;
    // Plusieurs artistes (feat., collaborations) separes individuellement
    // pour rester cliquables un par un, meme regex que desktop_player_bar.
    final artistNames = track.artist
        .split(RegExp(r'[/&,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (artistNames.isEmpty) artistNames.add(track.artist);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: isPlaceholder
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isPlaceholder ? null : widget.onTap,
        child: Opacity(
          opacity: isPlaceholder ? 0.45 : 1.0,
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color:
                  _hover ? Colors.white.withOpacity(0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(DesktopGlass.radiusSm),
            ),
            child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF3E3E3E),
                  borderRadius: BorderRadius.circular(6),
                  image: path != null
                      ? DecorationImage(
                          image: coverImageProvider(context,
                              path: path, width: 40, height: 40),
                          fit: BoxFit.cover,
                          onError: (_, __) {},
                        )
                      : null,
                ),
                child: path == null
                    ? const Icon(Icons.music_note,
                        color: Colors.white54, size: 18)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.isPlaying
                            ? DesktopGlass.accent
                            : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < artistNames.length; i++) ...[
                          if (i > 0)
                            const Text(', ',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                          Flexible(
                            child: _HoverableText(
                              text: artistNames[i],
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                              onTap: widget.onOpenArtist == null
                                  ? null
                                  : () => widget.onOpenArtist!(artistNames[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: _HoverableText(
                  text: track.album,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  onTap: widget.onOpenAlbum,
                ),
              ),
              if (isPlaceholder) ...[
                const Icon(Icons.error_outline,
                    color: Colors.orange, size: 16),
                const SizedBox(width: 6),
                const Text('Introuvable',
                    style: TextStyle(color: Colors.orange, fontSize: 12)),
              ] else ...[
                SizedBox(
                  width: 56,
                  child: Text(
                    formatDuration(track.duration),
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                GlassIconButton(
                  icon:
                      track.isLiked ? Icons.favorite : Icons.favorite_border,
                  color:
                      track.isLiked ? DesktopGlass.accent : Colors.white54,
                  size: 18,
                  onPressed: widget.onLike,
                ),
                GlassIconButton(
                  key: _moreButtonKey,
                  icon: Icons.more_horiz,
                  color: Colors.white54,
                  size: 18,
                  onPressed: _showMoreMenu,
                ),
              ],
            ],
          ),
          ),
        ),
      ),
    );
  }
}

/// Texte souligne au survol quand cliquable (artiste -> page artiste, album
/// -> page album), comme un lien -- meme widget que desktop_player_bar.
class _HoverableText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final VoidCallback? onTap;

  const _HoverableText({
    required this.text,
    required this.style,
    required this.onTap,
  });

  @override
  State<_HoverableText> createState() => _HoverableTextState();
}

class _HoverableTextState extends State<_HoverableText> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.onTap != null && _hover
        ? widget.style.copyWith(decoration: TextDecoration.underline)
        : widget.style;

    final text = Text(widget.text,
        maxLines: 1, overflow: TextOverflow.ellipsis, style: style);

    if (widget.onTap == null) return text;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: text),
    );
  }
}
