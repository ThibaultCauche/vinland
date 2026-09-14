import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/album.dart';
import '../models/track.dart';
import '../widgets/smooth_scroll.dart';
import 'desktop_hero_card.dart';
import 'desktop_track_row.dart';
import 'glass.dart';

/// Vue generique "collection de titres" (playlist, album ou artiste) :
/// hero card + liste, reutilisee par les trois car la reference Behance
/// montre exactement cette mise en page pour une playlist.
///
/// Le tout vit dans un seul CustomScrollView (hero card + liste des titres
/// comme slivers d'un meme Scrollable) plutot qu'une hero card fixe au-dessus
/// d'une ListView independante : sinon la molette ne fait defiler que quand
/// le curseur survole precisement la liste, pas le reste de la page (aucun
/// Scrollable ancetre au-dessus d'elle). Ca permet aussi a la hero card de se
/// reduire "gratuitement" via le protocole SliverPersistentHeader
/// (shrinkOffset fourni par le framework) plutot qu'un listener de scroll
/// manuel qui recalculait une hauteur en concurrence avec le defilement
/// qu'il etait cense suivre.
class DesktopCollectionView extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? coverPath;
  final List<Track> tracks;
  final bool? isLiked;
  final VoidCallback? onToggleLike;
  final VoidCallback onBack;
  // Optionnels : sans eux la colonne album / les noms d'artiste des lignes
  // restent de simples textes non cliquables (voir DesktopTrackRow).
  final void Function(Album album)? onOpenAlbum;
  final void Function(String artistName)? onOpenArtist;
  // Non-null uniquement pour une playlist (pas de sens pour "Titres likes",
  // seul autre appelant de cette vue).
  final VoidCallback? onShare;
  final VoidCallback? onSendToFriend;

  const DesktopCollectionView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.coverPath,
    required this.tracks,
    required this.onBack,
    this.isLiked,
    this.onToggleLike,
    this.onOpenAlbum,
    this.onOpenArtist,
    this.onShare,
    this.onSendToFriend,
  });

  @override
  State<DesktopCollectionView> createState() => _DesktopCollectionViewState();
}

class _DesktopCollectionViewState extends State<DesktopCollectionView> {
  final _scrollController = SmoothScrollController();
  // null = pas de filtre (tous les titres). Le genre vient des metadonnees
  // Navidrome (Track.genre) -- absent pour les titres importes localement.
  String? _selectedGenre;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Genres distincts presents dans la collection, du plus frequent au moins
  /// frequent (comme les puces de filtre Spotify). Vide si les titres n'ont
  /// pas de genre ou n'en ont qu'un seul en commun -- un filtre a une seule
  /// valeur possible n'apporte rien.
  List<String> _distinctGenres(List<Track> tracks) {
    final counts = <String, int>{};
    for (final t in tracks) {
      final g = t.genre?.trim();
      if (g == null || g.isEmpty) continue;
      counts[g] = (counts[g] ?? 0) + 1;
    }
    if (counts.length < 2) return const [];
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final subtitle = widget.subtitle;
    final coverPath = widget.coverPath;
    final tracks = widget.tracks;
    final isLiked = widget.isLiked;
    final onToggleLike = widget.onToggleLike;
    final onBack = widget.onBack;
    final state = context.read<AppState>();
    final songCount = '${tracks.length} titre${tracks.length > 1 ? 's' : ''}';

    final genres = _distinctGenres(tracks);
    final selectedGenre =
        genres.contains(_selectedGenre) ? _selectedGenre : null;
    final filteredTracks = selectedGenre == null
        ? tracks
        : tracks.where((t) => t.genre?.trim() == selectedGenre).toList();
    // Titres "Titres likes" importes via CSV mais introuvables sur le NAS
    // (Track.isPlaceholder) : affiches grises dans la liste (DesktopTrackRow)
    // mais jamais dans une file de lecture -- pas de fichier reel a jouer.
    // Sans objet pour album/playlist/artiste (aucun placeholder n'y figure),
    // donc identique a filteredTracks partout ailleurs.
    final playableTracks =
        filteredTracks.where((t) => !t.isPlaceholder).toList();

    // Resolution album par titre calculee une fois par build (pas par ligne)
    // pour eviter de rescanner state.albums a chaque item de la liste.
    final albumByTrackId = <String, Album>{};
    if (widget.onOpenAlbum != null) {
      for (final album in state.albums) {
        for (final id in album.trackIds) {
          albumByTrackId[id] = album;
        }
      }
    }

    // topInsetCompact (pas topInset) : cette vue poussee dans la pile n'a
    // pas la barre de recherche persistante du TopBar (masquee ici, voir
    // _TopBar.showSearchBar), donc pas besoin de lui reserver sa place --
    // seule la barre de titre custom compte, sinon un grand vide separait
    // le haut de la fenetre du bloc titre/cover (retour testeurs).
    return Padding(
      padding: const EdgeInsets.only(top: DesktopGlass.topInsetCompact),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _CollapsingHeroDelegate(
              title: title,
              subtitle: subtitle,
              metaLabel: songCount,
              coverPath: coverPath,
              isLiked: isLiked ?? false,
              onToggleLike: onToggleLike,
              onBack: onBack,
              onShuffle: playableTracks.isEmpty
                  ? () {}
                  : () {
                      final shuffled = List<Track>.of(playableTracks)
                        ..shuffle();
                      state.playTrack(shuffled.first, trackList: shuffled);
                    },
              onShare: widget.onShare,
              onSendToFriend: widget.onSendToFriend,
            ),
          ),
          // 20 -> 10 : l'espace entre le bloc et la liste etait trop
          // genereux, cumule avec la marge bottom:8 du delegate (retour
          // testeurs : "moins d'espace en bas du bloc").
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          if (genres.isNotEmpty)
            SliverToBoxAdapter(
              child: _GenreChipsBar(
                genres: genres,
                selected: selectedGenre,
                onSelect: (g) => setState(
                    () => _selectedGenre = g == _selectedGenre ? null : g),
              ),
            ),
          if (filteredTracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('Aucun titre',
                    style: TextStyle(color: Colors.white38)),
              ),
            )
          else
            Selector<AppState, Track?>(
              selector: (_, s) => s.currentTrack,
              builder: (context, currentTrack, __) {
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final track = filteredTracks[i];
                      final album = albumByTrackId[track.id];
                      return DesktopTrackRow(
                        track: track,
                        isPlaying: currentTrack?.id == track.id,
                        onTap: () => state.playTrack(track,
                            trackList: playableTracks),
                        onLike: () => state.toggleLike(track.id),
                        onMore: () {},
                        onOpenAlbum: album == null || widget.onOpenAlbum == null
                            ? null
                            : () => widget.onOpenAlbum!(album),
                        onOpenArtist: widget.onOpenArtist,
                      );
                    },
                    childCount: filteredTracks.length,
                  ),
                );
              },
            ),
          const SliverToBoxAdapter(
              child: SizedBox(height: DesktopGlass.playerBarReserve)),
        ],
      ),
    );
  }
}

/// Rangee de puces de filtre par genre (defilement horizontal), au-dessus de
/// la liste -- comme le fait Spotify sur "Titres likes". Retape sur la puce
/// selectionnee pour revenir a "tous les titres".
class _GenreChipsBar extends StatelessWidget {
  final List<String> genres;
  final String? selected;
  final void Function(String genre) onSelect;

  const _GenreChipsBar({
    required this.genres,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: genres.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final genre = genres[i];
          final isSelected = genre == selected;
          return _GenreChip(
            label: genre,
            selected: isSelected,
            onTap: () => onSelect(genre),
          );
        },
      ),
    );
  }
}

class _GenreChip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GenreChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_GenreChip> createState() => _GenreChipState();
}

class _GenreChipState extends State<_GenreChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white
                : Colors.white.withOpacity(_hover ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Delegate du header retractable : etendu (232px) en haut de page, reduit
/// a 96px une fois qu'on a defile d'autant, puis reste epingle a cette
/// taille minimale (pinned: true ci-dessus) pour continuer a montrer le
/// titre de la collection pendant qu'on parcourt la liste.
class _CollapsingHeroDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final String subtitle;
  final String metaLabel;
  final String? coverPath;
  final bool isLiked;
  final VoidCallback? onToggleLike;
  final VoidCallback onShuffle;
  final VoidCallback onBack;
  final VoidCallback? onShare;
  final VoidCallback? onSendToFriend;

  _CollapsingHeroDelegate({
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
  });

  static const double _maxExtent = 220;
  // Doit rester synchronisee avec la hauteur minimale de DesktopHeroCard
  // (_lerp(220, 88, shrink)) : le titre + like + lecture aleatoire sont
  // etales sur une seule ligne une fois reduit (pas empiles), donc pas
  // besoin d'une barre aussi haute que lorsqu'ils etaient sur 2 "etages".
  static const double _minExtent = 88;

  // Seuil de bascule plein format <-> reduit, partage avec DesktopHeroCard
  // (showSubtitle) : sous ce seuil, la fleche retour flottante ci-dessous
  // laisse place a celle integree a la ligne titre/bouton de DesktopHeroCard.
  static const double _compactThreshold = 0.55;

  @override
  double get maxExtent => _maxExtent;

  @override
  double get minExtent => _minExtent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final double shrink =
        (shrinkOffset / (_maxExtent - _minExtent)).clamp(0.0, 1.0);
    // Plein format : fleche flottante au-dessus de l'image, coin superieur
    // gauche. Reduit : DesktopHeroCard integre sa propre fleche dans la
    // ligne titre/bouton (retour testeurs : la fleche flottante etait mal
    // placee une fois la barre reduite) -- les deux sont donc exclusives.
    final bool expanded = shrink < _compactThreshold;
    return Padding(
      // right: 24 -- marge du bloc entier par rapport au bord de la
      // fenetre (retour testeurs), pas seulement de l'image a l'interieur.
      padding: const EdgeInsets.only(bottom: 4, right: 24),
      child: Stack(
        children: [
          DesktopHeroCard(
            title: title,
            subtitle: subtitle,
            metaLabel: metaLabel,
            coverPath: coverPath,
            isLiked: isLiked,
            onToggleLike: onToggleLike,
            onShuffle: onShuffle,
            onBack: onBack,
            onShare: onShare,
            onSendToFriend: onSendToFriend,
            shrink: shrink,
          ),
          if (expanded)
            Positioned(
              top: 12,
              left: 12,
              child: GlassIconButton(
                  icon: Icons.arrow_back_rounded, onPressed: onBack),
            ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CollapsingHeroDelegate oldDelegate) {
    return title != oldDelegate.title ||
        subtitle != oldDelegate.subtitle ||
        metaLabel != oldDelegate.metaLabel ||
        coverPath != oldDelegate.coverPath ||
        isLiked != oldDelegate.isLiked ||
        onToggleLike != oldDelegate.onToggleLike ||
        onShuffle != oldDelegate.onShuffle ||
        onBack != oldDelegate.onBack ||
        onShare != oldDelegate.onShare ||
        onSendToFriend != oldDelegate.onSendToFriend;
  }
}
