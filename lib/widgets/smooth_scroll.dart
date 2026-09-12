import 'package:flutter/widgets.dart';

/// [ScrollController] qui anime les evenements de molette de souris au lieu
/// du saut instantane applique par defaut par Flutter.
///
/// Scrollable._receivedPointerSignal() appelle position.pointerScroll(delta)
/// DIRECTEMENT sur un evenement de molette, quelle que soit la ScrollPhysics
/// choisie (seuls le trackpad/tactile passent par l'animation "ballistic"
/// normale) -- donc intercepter l'evenement en amont (ex: un Listener
/// ancetre + PointerSignalResolver) ne marche pas : le Listener interne de
/// Scrollable, plus profond dans l'arbre que n'importe quel wrapper externe,
/// est toujours touche par le hit-test AVANT lui et remporte la resolution
/// (le PREMIER gestionnaire enregistre gagne). Le point d'extension prevu
/// par Flutter pour ce cas est ScrollPosition.pointerScroll lui-meme :
/// on fournit donc un ScrollController qui cree une ScrollPosition dont
/// pointerScroll() anime au lieu de sauter.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPositionWithSingleContext createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  DateTime? _lastEventTime;

  // Duree/courbe d'origine : chaque cran anime jusqu'a sa cible puis s'arrete
  // net, pour une sensation "seche" plutot qu'un glisse/inertie prolongee
  // (un essai precedent avec une simulation ballistique/goBallistic donnait
  // au contraire une impression de "glisser sur du beurre").
  static const Duration _animDuration = Duration(milliseconds: 260);

  // En dessous de ce delai entre deux crans, on considere que la molette est
  // actionnee vite/fort et on amplifie le deplacement de ce cran (jusqu'a
  // x2) au lieu de deplacer la meme distance fixe a chaque fois -- c'est ce
  // qui manquait a l'implementation d'origine (scroll "fort" = memes crans,
  // donc meme vitesse percue que scroll "doux").
  static const double _boostWindowMs = 60;

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) {
      goBallistic(0.0);
      return;
    }

    final now = DateTime.now();
    final double elapsedMs = _lastEventTime == null
        ? _boostWindowMs
        : now.difference(_lastEventTime!).inMicroseconds / 1000.0;
    _lastEventTime = now;

    final double boost = elapsedMs >= _boostWindowMs
        ? 1.0
        : (1.0 + (_boostWindowMs - elapsedMs) / _boostWindowMs).clamp(1.0, 2.0);

    final double targetPixels =
        (pixels + delta * boost).clamp(minScrollExtent, maxScrollExtent);
    if (targetPixels != pixels) {
      animateTo(targetPixels, duration: _animDuration, curve: Curves.easeOutCubic);
    }
  }
}
