import 'package:flutter/material.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../providers/app_state.dart';
import '../services/deep_link_service.dart';
import '../widgets/cover_image.dart';
import 'glass.dart';

/// Actions du menu "..." d'un titre individuel (lire ensuite, file
/// d'attente, partager, envoyer a un ami) -- memes entrees que
/// DesktopTrackRow (deja cablees partout : Titres likes, playlists, albums,
/// artistes, recherche), partagees ici pour _PopularTrackRow (page artiste,
/// section "Titres populaires") qui n'avait jusqu'ici aucune option du tout
/// (retour utilisateur).
List<DesktopHeroMenuAction> trackMoreMenuActions(
    BuildContext context, AppState state, Track track) {
  return [
    DesktopHeroMenuAction(
      label: 'Lire ensuite',
      icon: Icons.playlist_play,
      onTap: () => state.playNext(track),
    ),
    DesktopHeroMenuAction(
      label: "Ajouter à la file d'attente",
      icon: Icons.queue_music,
      onTap: () => state.addToQueue(track),
    ),
    DesktopHeroMenuAction(
      label: 'Partager',
      icon: Icons.ios_share,
      onTap: () => shareTrack(track),
    ),
    if (state.shareInboxConfigured)
      DesktopHeroMenuAction(
        label: 'Envoyer à un ami',
        icon: Icons.send_outlined,
        onTap: () => showSendToFriendDialog(context,
            type: 'track',
            itemId: track.id,
            title: track.title,
            subtitle: track.artist),
      ),
  ];
}

/// Ouvre un choix de playlist et y ajoute tous les [tracks] -- partage par
/// DesktopAlbumView et DesktopDiscoveredAlbumView pour leur action "Ajouter
/// a une playlist" du menu "...".
Future<void> pickPlaylistAndAddTracks(
    BuildContext context, AppState state, List<Track> tracks) async {
  final playlists = state.playlists;
  final playlist = await showDialog<Playlist>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Ajouter à une playlist',
          style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 320,
        child: playlists.isEmpty
            ? const Text('Aucune playlist pour le moment.',
                style: TextStyle(color: Colors.white70))
            : ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, i) {
                  final pl = playlists[i];
                  return ListTile(
                    title: Text(pl.name,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text('${pl.trackIds.length} titre(s)',
                        style: const TextStyle(color: Colors.white54)),
                    onTap: () => Navigator.pop(ctx, pl),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuler'),
        ),
      ],
    ),
  );
  if (playlist == null || !context.mounted) return;
  for (final t in tracks) {
    await state.addToPlaylist(playlist.id, t.id);
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ajouté à "${playlist.name}"')),
    );
  }
}

/// Grande carte d'en-tete d'une playlist/album/artiste : cover en fond a
/// droite, degrade sombre a gauche pour la lisibilite du texte, titre,
/// sous-titre, compteur et bouton "Lecture aleatoire" -- comme la reference.
double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Une entree du menu "..." (voir moreActions) -- l'appelant (DesktopAppShell)
/// fournit la liste toute prete pour que cette carte reste sans logique
/// metier, comme onShare/onSendToFriend.
class DesktopHeroMenuAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;

  const DesktopHeroMenuAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });
}

class DesktopHeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String metaLabel;
  final String? coverPath;
  final bool isLiked;
  final VoidCallback? onToggleLike;
  final VoidCallback onShuffle;

  /// Non-null uniquement pour une playlist (voir DesktopCollectionView) :
  /// pas de sens pour "Titres likes", seul autre appelant de cette carte.
  final VoidCallback? onShare;

  /// Meme principe que onShare, pour "Envoyer a un ami" (boite de reception,
  /// voir AppState.sendShareToFriend) -- masque quand le service n'est pas
  /// configure (voir AppState.shareInboxConfigured), a l'appelant de filtrer.
  final VoidCallback? onSendToFriend;

  /// Actions du menu "..." (file d'attente, telechargement, rendre
  /// privee/publique, supprimer...) -- vide (defaut) pour ne pas afficher le
  /// bouton, comme "Titres likes" qui n'a pas de playlist reelle derriere.
  final List<DesktopHeroMenuAction> moreActions;

  /// 0 = carte pleine taille, 1 = reduite au minimum (voir
  /// DesktopCollectionView, qui le pilote a partir du defilement de la
  /// liste en dessous plutot que de laisser la carte occuper tout cet
  /// espace en permanence).
  final double shrink;

  const DesktopHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.metaLabel,
    required this.coverPath,
    required this.onShuffle,
    this.isLiked = false,
    this.onToggleLike,
    this.onShare,
    this.onSendToFriend,
    this.moreActions = const [],
    this.shrink = 0,
  });

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final double height = _lerp(220, 88, shrink);
    final double titleSize = _lerp(30, 20, shrink);
    final double pad = _lerp(28, 18, shrink);
    // Sous-titre + compteur de titres seuls disparaissent une fois reduit
    // (texte purement informatif) -- le bouton like + lecture aleatoire
    // reste lui toujours visible juste en dessous (voir Row plus bas) :
    // sans action utile, epingler cette barre reduite au scroll n'avait
    // pas grand interet (retour testeurs).
    final bool showSubtitle = shrink < 0.55;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Decode toujours a la taille MAX (pas la hauteur courante,
          // animee par shrink) : sinon chaque frame du collapse redecoderait
          // la cover a une taille differente au lieu de reutiliser le cache.
          final double boxWidth =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 1200;
          return GlassPanel(
            borderRadius: BorderRadius.circular(DesktopGlass.radiusLg),
            tint: Colors.transparent,
            blurSigma: 0,
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Fond opaque garanti sous l'image : le dernier stop du
                // degrade ci-dessous descend a 0.05 d'opacite cote droit
                // (pour laisser voir la cover), donc sans ce fond une cover
                // qui ne couvre pas tout le cadre (image cassee, chargement,
                // ratio inattendu) laissait la liste de titres en dessous
                // transparaitre a travers le bandeau.
                const DecoratedBox(
                    decoration: BoxDecoration(color: Color(0xFF1A1A1A))),
                if (path != null)
                  // La marge demandee (retour testeurs) est celle du BLOC
                  // entier par rapport au bord de la fenetre, pas de l'image
                  // a l'interieur de son bloc -- voir le Padding ajoute
                  // autour de DesktopHeroCard dans DesktopCollectionView.
                  // L'image ici reste donc plein cadre, comme a l'origine.
                  Image(
                    // height: boxWidth (pas 220, la hauteur AFFICHEE) --
                    // coverImageProvider decode a la taille demandee en
                    // supposant qu'elle correspond au rendu final, correct
                    // pour un BoxFit.contain mais pas ici : ce bandeau est
                    // affiche en BoxFit.cover, tres large et bas, donc le
                    // decodage doit se caler sur la LARGEUR (ce que cover
                    // utilise reellement pour une cover source proche du
                    // carre) plutot que sur les 220px de hauteur -- sinon
                    // l'image decodee a ~220px de cote est ensuite etiree
                    // sur toute la largeur du bandeau et devient tres
                    // pixelisee (retour utilisateur).
                    image: coverImageProvider(context,
                        path: path, width: boxWidth, height: boxWidth),
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    // Qualite haute seulement ici (le gros bloc titre/cover,
                    // ou l'upscale d'une cover source basse resolution se
                    // voit) -- pas sur les petites vignettes (48px) de la
                    // liste de titres, ou le cout GPU par frame ne vaut pas
                    // le gain invisible a cette taille (retour testeurs).
                    filterQuality: FilterQuality.high,
                    errorBuilder: (context, error, stackTrace) =>
                        const DecoratedBox(
                            decoration:
                                BoxDecoration(color: Color(0xFF2A2A2A))),
                  )
                else
                  const DecoratedBox(
                      decoration: BoxDecoration(color: Color(0xFF2A2A2A))),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withOpacity(0.75),
                        Colors.black.withOpacity(0.55),
                        Colors.black.withOpacity(0.05),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(pad),
                  child: showSubtitle
                      // Plein format : titre/sous-titre/actions empiles,
                      // centres verticalement dans le bloc. SingleChildScrollView
                      // (pas juste Column) : entre le seuil de bascule vers le
                      // format reduit (shrink 0.55) et ce seuil, la hauteur du
                      // bandeau (_lerp(220,88,shrink)) devient plus petite que
                      // ce dont la colonne a besoin (titre+sous-titre+rangee de
                      // boutons), ce qui provoquait un vrai "RenderFlex
                      // overflowed" pendant le defilement (retour
                      // utilisateur). Les espacements/maxLines ci-dessous sont
                      // deja resserres pour limiter au maximum ce cas, ce
                      // scroll ne sert que de filet de securite s'il reste
                      // trop juste.
                      ? SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: titleSize,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: _lerp(8, 2, shrink)),
                            SizedBox(
                              width: 420,
                              child: Text(
                                subtitle,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 14),
                                // 1 ligne (pas 2) : la ligne en trop etait la
                                // premiere source du manque de place pendant
                                // la transition.
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(height: _lerp(20, 8, shrink)),
                            Row(
                              children: [
                                if (onToggleLike != null)
                                  _LikeIcon(
                                      isLiked: isLiked, onTap: onToggleLike!),
                                if (onToggleLike != null)
                                  const SizedBox(width: 8),
                                Text(metaLabel,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12)),
                                const SizedBox(width: 20),
                                _ShufflePill(onTap: onShuffle),
                                if (onShare != null) ...[
                                  const SizedBox(width: 8),
                                  GlassIconButton(
                                      icon: Icons.ios_share, onPressed: onShare!),
                                ],
                                if (onSendToFriend != null) ...[
                                  const SizedBox(width: 8),
                                  GlassIconButton(
                                      icon: Icons.send_outlined,
                                      onPressed: onSendToFriend!),
                                ],
                                if (moreActions.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  DesktopMoreMenuButton(actions: moreActions),
                                ],
                              ],
                            ),
                          ],
                          ),
                        )
                      // Reduit : titre - boutons, sur une seule ligne plutot
                      // qu'empiles sur 2 "etages" (ca debordait d'une barre
                      // volontairement basse, et etait moins lisible --
                      // retour testeurs). Meme rangee de boutons qu'en plein
                      // format (pas juste "Lecture aleatoire") : les garder
                      // tous utilisables pendant le defilement plutot que de
                      // les faire disparaitre avec le sous-titre (retour
                      // utilisateur). Plus de fleche retour ici : la
                      // navigation avant/arriere vit desormais dans la barre
                      // de titre du shell (voir DesktopTitleBar), l'avoir
                      // aussi ici etait redondant.
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 16),
                            if (onToggleLike != null) ...[
                              _LikeIcon(isLiked: isLiked, onTap: onToggleLike!),
                              const SizedBox(width: 8),
                            ],
                            _ShufflePill(onTap: onShuffle),
                            if (onShare != null) ...[
                              const SizedBox(width: 8),
                              GlassIconButton(
                                  icon: Icons.ios_share, onPressed: onShare!),
                            ],
                            if (onSendToFriend != null) ...[
                              const SizedBox(width: 8),
                              GlassIconButton(
                                  icon: Icons.send_outlined,
                                  onPressed: onSendToFriend!),
                            ],
                            if (moreActions.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              DesktopMoreMenuButton(actions: moreActions),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Bouton "..." qui ouvre un menu ancre sur lui-meme -- meme mecanisme que
/// _ProfileAvatarButton dans desktop_sidebar.dart (RenderBox du bouton lui
/// meme, pas de la carte entiere, pour un menu qui s'ouvre juste a cote).
/// Public : reutilise par DesktopAlbumView pour son propre menu "...".
class DesktopMoreMenuButton extends StatelessWidget {
  final List<DesktopHeroMenuAction> actions;
  const DesktopMoreMenuButton({super.key, required this.actions});

  void _showMenu(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: true);
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
        for (final a in actions)
          PopupMenuItem(
            onTap: a.onTap,
            child: Row(
              children: [
                Icon(a.icon,
                    size: 18,
                    color: a.destructive ? Colors.redAccent : Colors.white70),
                const SizedBox(width: 12),
                Text(a.label,
                    style: TextStyle(
                        color: a.destructive ? Colors.redAccent : Colors.white)),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassIconButton(
        icon: Icons.more_horiz, onPressed: () => _showMenu(context));
  }
}

class _LikeIcon extends StatelessWidget {
  final bool isLiked;
  final VoidCallback onTap;
  const _LikeIcon({required this.isLiked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DesktopHoverable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          isLiked ? Icons.favorite : Icons.favorite_border,
          color: isLiked ? DesktopGlass.accent : Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

class _ShufflePill extends StatelessWidget {
  final VoidCallback onTap;
  const _ShufflePill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.18),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Lecture aleatoire',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              SizedBox(width: 8),
              Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
