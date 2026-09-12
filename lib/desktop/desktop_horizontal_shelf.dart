import 'package:flutter/material.dart';
import '../widgets/smooth_scroll.dart';

/// Etagere horizontale reutilisable (shelves de la home, resultats artistes
/// de la recherche, singles d'un artiste...) : molette lissee comme le
/// reste de l'app (SmoothScrollController) + fleches gauche/droite qui
/// n'apparaissent que quand il y a effectivement quelque chose a voir dans
/// cette direction -- une souris sans molette horizontale n'a sinon aucun
/// moyen de faire defiler ces etageres.
class DesktopHorizontalShelf extends StatefulWidget {
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry? padding;
  final double scrollByAmount;

  const DesktopHorizontalShelf({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
    this.scrollByAmount = 600,
  });

  @override
  State<DesktopHorizontalShelf> createState() => _DesktopHorizontalShelfState();
}

class _DesktopHorizontalShelfState extends State<DesktopHorizontalShelf> {
  final _controller = SmoothScrollController();
  bool _canScrollBack = false;
  bool _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void didUpdateWidget(covariant DesktopHorizontalShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
    }
  }

  void _updateArrows() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final canBack = position.pixels > position.minScrollExtent + 1;
    final canForward = position.pixels < position.maxScrollExtent - 1;
    if (canBack != _canScrollBack || canForward != _canScrollForward) {
      setState(() {
        _canScrollBack = canBack;
        _canScrollForward = canForward;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_updateArrows);
    _controller.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (_controller.offset + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _controller.animateTo(target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _updateArrows());
              return false;
            },
            child: ListView.builder(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: widget.padding,
              itemCount: widget.itemCount,
              itemBuilder: widget.itemBuilder,
            ),
          ),
          if (_canScrollBack)
            Positioned(
              left: 0,
              child: _ShelfArrow(
                icon: Icons.chevron_left,
                onTap: () => _scrollBy(-widget.scrollByAmount),
              ),
            ),
          if (_canScrollForward)
            Positioned(
              right: 0,
              child: _ShelfArrow(
                icon: Icons.chevron_right,
                onTap: () => _scrollBy(widget.scrollByAmount),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShelfArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ShelfArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
