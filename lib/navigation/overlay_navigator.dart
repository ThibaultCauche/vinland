import 'package:flutter/widgets.dart';

import '../models/album.dart';
import '../models/playlist.dart';

/// Ecran plein page qui ne doit exister qu'une fois dans la pile : le big
/// player et la file d'attente ont chacun un point d'entree persistant
/// (mini-player, bouton file d'attente) qui peut etre retape alors que
/// l'autre est deja ouvert plus bas -- sans ce garde-fou, l'aller-retour
/// entre les deux les empilait a l'infini au lieu de faire simplement
/// remonter l'ecran existant.
abstract interface class SingleInstanceOverlay {}

/// Ecran qu'on n'empile pas deux fois de suite pour le meme contenu (ex: la
/// meme page artiste).
abstract interface class KeyedOverlay {
  Object get overlayKey;
}

/// Pile des ecrans plein page mobiles (voir pushOverlay). Sortie d'AppState
/// pour qu'il n'importe plus aucun ecran : ce sont les ecrans qui declarent
/// leur regle d'empilement (SingleInstanceOverlay, KeyedOverlay).
class OverlayNavigator extends ChangeNotifier {
  final List<Widget> _stack = [];
  List<Widget> get stack => List.unmodifiable(_stack);
  Widget? get current => _stack.isNotEmpty ? _stack.last : null;

  /// Le shell desktop (DesktopAppShell) a sa propre pile de navigation
  /// locale, separee de cette pile pensee pour des ecrans mobiles pleine
  /// page -- voir le commentaire sur DesktopAppShell. Il s'enregistre ici a
  /// son montage pour que du code qui n'a pas acces a son State (ex:
  /// openSharedItem, qui ouvre un album/playlist partage) puisse l'atteindre
  /// quelle que soit la plateforme.
  void Function(Album album)? onDesktopOpenAlbum;
  void Function(Playlist playlist)? onDesktopOpenPlaylist;

  void push(Widget screen) {
    final Object? last = current;
    final Object incoming = screen;
    if (last is KeyedOverlay &&
        incoming is KeyedOverlay &&
        last.runtimeType == incoming.runtimeType &&
        last.overlayKey == incoming.overlayKey) {
      return;
    }
    if (screen is SingleInstanceOverlay) {
      final existingIndex =
          _stack.indexWhere((w) => w.runtimeType == screen.runtimeType);
      if (existingIndex != -1) {
        _stack.removeRange(existingIndex, _stack.length);
      }
    }
    _stack.add(screen);
    notifyListeners();
  }

  void pop() {
    if (_stack.isNotEmpty) {
      _stack.removeLast();
      notifyListeners();
    }
  }

  void clear() {
    _stack.clear();
    notifyListeners();
  }
}
