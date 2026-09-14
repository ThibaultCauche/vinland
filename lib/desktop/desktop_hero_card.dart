import 'package:flutter/material.dart';
import '../widgets/cover_image.dart';
import 'glass.dart';

/// Grande carte d'en-tete d'une playlist/album/artiste : cover en fond a
/// droite, degrade sombre a gauche pour la lisibilite du texte, titre,
/// sous-titre, compteur et bouton "Lecture aleatoire" -- comme la reference.
double _lerp(double a, double b, double t) => a + (b - a) * t;

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

  /// Appele par la fleche retour integree a la ligne du format reduit (voir
  /// plus bas) -- en plein format, la fleche flottante au-dessus de l'image
  /// reste geree par DesktopCollectionView (_CollapsingHeroDelegate).
  final VoidCallback onBack;

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
    required this.onBack,
    this.isLiked = false,
    this.onToggleLike,
    this.onShare,
    this.onSendToFriend,
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
                    image: coverImageProvider(context,
                        path: path, width: boxWidth, height: 220),
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
                      // centres verticalement dans le bloc.
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
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
                            const SizedBox(height: 8),
                            SizedBox(
                              width: 420,
                              child: Text(
                                subtitle,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 14),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 20),
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
                              ],
                            ),
                          ],
                        )
                      // Reduit : fleche retour - 10px - titre - 10px -
                      // bouton, etales sur une seule ligne plutot
                      // qu'empiles sur 2 "etages" (ca debordait d'une barre
                      // volontairement basse, et etait moins lisible --
                      // retour testeurs). La fleche vit ici (et plus en
                      // Positioned flottant, voir DesktopCollectionView) :
                      // integree a la ligne comme demande, pas au-dessus de
                      // l'image.
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              GlassIconButton(
                                  icon: Icons.arrow_back_rounded,
                                  onPressed: onBack),
                              const SizedBox(width: 10),
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
                              const SizedBox(width: 10),
                              _ShufflePill(onTap: onShuffle),
                            ],
                          ),
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
