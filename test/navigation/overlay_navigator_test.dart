import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/navigation/overlay_navigator.dart';

class _Page extends StatelessWidget {
  const _Page();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _Unique extends StatelessWidget implements SingleInstanceOverlay {
  const _Unique();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _OtherUnique extends StatelessWidget implements SingleInstanceOverlay {
  const _OtherUnique();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _Keyed extends StatelessWidget implements KeyedOverlay {
  const _Keyed(this.name);
  final String name;
  @override
  Object get overlayKey => name;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  late OverlayNavigator nav;
  late int notified;
  setUp(() {
    nav = OverlayNavigator();
    notified = 0;
    nav.addListener(() => notified++);
  });

  test('empile, depile et vide', () {
    expect(nav.current, isNull);
    nav.push(const _Page());
    nav.push(const _Page());
    expect(nav.stack.length, 2);
    nav.pop();
    expect(nav.stack.length, 1);
    nav.clear();
    expect(nav.current, isNull);
    nav.pop(); // pile vide : rien
    expect(notified, 4);
  });

  test('meme page artiste tapee deux fois de suite : une seule page', () {
    nav.push(const _Keyed('Daft Punk'));
    nav.push(const _Keyed('Daft Punk'));
    expect(nav.stack.length, 1);
    nav.push(const _Keyed('Justice'));
    expect(nav.stack.length, 2);
  });

  test(
      'aller-retour big player / file d\'attente : remonte l\'ecran existant '
      'au lieu d\'empiler a l\'infini', () {
    nav.push(const _Page());
    nav.push(const _Unique());
    nav.push(const _OtherUnique());
    nav.push(const _Unique());
    expect(nav.stack.map((w) => w.runtimeType), [_Page, _Unique]);
    nav.push(const _OtherUnique());
    nav.push(const _Unique());
    nav.push(const _OtherUnique());
    expect(nav.stack.map((w) => w.runtimeType), [_Page, _Unique, _OtherUnique]);
  });
}
