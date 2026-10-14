import 'dart:async';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../desktop/desktop_theme.dart';
import '../services/subsonic_refs.dart';
import '../widgets/cover_image.dart';
import 'mobile_theme.dart';
import 'solid_color_effect.dart';

/// Apparence de l'app : themes de fond desktop et mobile (persistes) et
/// couleur d'ambiance tiree de la pochette du titre en cours. Sorti
/// d'AppState, qui garde pour l'instant des accesseurs qui delegue ici pour
/// ne pas toucher tous les ecrans d'un coup.
class ThemeController extends ChangeNotifier {
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Charge les reglages persistes (appele une fois par AppState.initialize).
  Future<void> load() async {
    _desktopThemeMode = await DesktopTheme.loadMode();
    _desktopThemeColor = await DesktopTheme.loadColor();
    _desktopCoverBlurSigma = await DesktopTheme.loadBlurSigma();
    _mobileThemeMode = await MobileTheme.loadMode();
    _mobileThemeColor = await MobileTheme.loadColor();
    _mobileCoverBlurSigma = await MobileTheme.loadBlurSigma();
    _mobileSolidEffect = await MobileTheme.loadSolidEffect();
    _desktopSolidEffect = await DesktopTheme.loadSolidEffect();
    // Une pochette epinglee avant la 1.3 etait stockee en URL complete
    // (avec jeton) : convertie en reference et reecrite une fois.
    final mobilePinned = await MobileTheme.loadPinnedCover();
    _mobilePinnedCoverPath = SubsonicRefs.toStorable(mobilePinned);
    if (_mobilePinnedCoverPath != mobilePinned) {
      await MobileTheme.savePinnedCover(_mobilePinnedCoverPath);
    }
    final desktopPinned = await DesktopTheme.loadPinnedCover();
    _desktopPinnedCoverPath = SubsonicRefs.toStorable(desktopPinned);
    if (_desktopPinnedCoverPath != desktopPinned) {
      await DesktopTheme.savePinnedCover(_desktopPinnedCoverPath);
    }
  }

  // Theme du fond desktop (voir desktop/desktop_theme.dart) : solide (couleur
  // RGB choisie par l'utilisateur), cover floutee, ou fenetre transparente
  // (experimental, depend du support de flutter_acrylic sur la machine).
  DesktopThemeMode _desktopThemeMode = DesktopThemeMode.solid;
  DesktopThemeMode get desktopThemeMode => _desktopThemeMode;
  Color _desktopThemeColor = DesktopTheme.defaultColor;
  Color get desktopThemeColor => _desktopThemeColor;

  Future<void> setDesktopThemeMode(DesktopThemeMode mode) async {
    _desktopThemeMode = mode;
    await DesktopTheme.saveMode(mode);
    _notify();
  }

  Future<void> setDesktopThemeColor(Color color) async {
    _desktopThemeColor = color;
    await DesktopTheme.saveColor(color);
    _notify();
  }

  double _desktopCoverBlurSigma = DesktopTheme.defaultBlurSigma;
  double get desktopCoverBlurSigma => _desktopCoverBlurSigma;

  Future<void> setDesktopCoverBlurSigma(double sigma) async {
    _desktopCoverBlurSigma = sigma;
    await DesktopTheme.saveBlurSigma(sigma);
    _notify();
  }

  SolidColorEffect _desktopSolidEffect = SolidColorEffect.flat;
  SolidColorEffect get desktopSolidEffect => _desktopSolidEffect;

  Future<void> setDesktopSolidEffect(SolidColorEffect effect) async {
    _desktopSolidEffect = effect;
    await DesktopTheme.saveSolidEffect(effect);
    _notify();
  }

  // Reference sans jeton (voir SubsonicRefs) : c'est elle qui est
  // persistee, l'URL complete n'est reconstruite qu'a la lecture.
  String? _desktopPinnedCoverPath;
  String? get desktopPinnedCoverPath =>
      SubsonicRefs.resolve(_desktopPinnedCoverPath);

  Future<void> setDesktopPinnedCoverPath(String? path) async {
    _desktopPinnedCoverPath = SubsonicRefs.toStorable(path);
    await DesktopTheme.savePinnedCover(_desktopPinnedCoverPath);
    _notify();
  }

  // Theme du fond mobile (voir theme/mobile_theme.dart) : equivalent du theme
  // desktop ci-dessus, sans le mode transparent (pas de sens sur une app
  // mobile toujours plein ecran).
  MobileThemeMode _mobileThemeMode = MobileThemeMode.solid;
  MobileThemeMode get mobileThemeMode => _mobileThemeMode;
  Color _mobileThemeColor = MobileTheme.defaultColor;
  Color get mobileThemeColor => _mobileThemeColor;

  Future<void> setMobileThemeMode(MobileThemeMode mode) async {
    _mobileThemeMode = mode;
    await MobileTheme.saveMode(mode);
    _notify();
  }

  Future<void> setMobileThemeColor(Color color) async {
    _mobileThemeColor = color;
    await MobileTheme.saveColor(color);
    _notify();
  }

  double _mobileCoverBlurSigma = MobileTheme.defaultBlurSigma;
  double get mobileCoverBlurSigma => _mobileCoverBlurSigma;

  Future<void> setMobileCoverBlurSigma(double sigma) async {
    _mobileCoverBlurSigma = sigma;
    await MobileTheme.saveBlurSigma(sigma);
    _notify();
  }

  SolidColorEffect _mobileSolidEffect = SolidColorEffect.flat;
  SolidColorEffect get mobileSolidEffect => _mobileSolidEffect;

  Future<void> setMobileSolidEffect(SolidColorEffect effect) async {
    _mobileSolidEffect = effect;
    await MobileTheme.saveSolidEffect(effect);
    _notify();
  }

  String? _mobilePinnedCoverPath;
  String? get mobilePinnedCoverPath =>
      SubsonicRefs.resolve(_mobilePinnedCoverPath);

  Future<void> setMobilePinnedCoverPath(String? path) async {
    _mobilePinnedCoverPath = SubsonicRefs.toStorable(path);
    await MobileTheme.savePinnedCover(_mobilePinnedCoverPath);
    _notify();
  }

  // --- Couleur d'ambiance de la pochette en cours ----------------------

  Color? dominantColor;
  int _lastColorRequest = 0;
  final Map<String, Color> _colorCache = {};

  /// Extrait une couleur d'ambiance via PaletteGenerator : quantifie l'image
  /// entiere et ponderee par population/saturation, plutot que l'ancienne
  /// moyenne brute de 5 pixels fixes (centre + coins), qui pouvait tomber
  /// sur un detail non representatif et produire une couleur "boueuse"
  /// n'apparaissant nulle part sur la cover.
  ///
  /// La swatch "dominant" (la plus etendue en surface) est la couleur de la
  /// pochette : une cover presque blanche avec un petit detail rouge doit
  /// donner du gris clair, pas du rouge vif (retour de Thibault, 2.2). Seule
  /// exception : une dominante tres sombre (fond noir + logo colore) se
  /// fondrait dans le noir de l'ecran, on prend alors l'accent colore
  /// ("vibrant"), qui rend la cover reconnaissable.
  Future<Color?> _extractDominantColor(String coverPath) async {
    try {
      final ImageProvider provider = rawCoverImageProvider(coverPath);
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(100, 100),
      );
      final dominant = palette.dominantColor?.color;
      final accent = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.mutedColor?.color;
      if (dominant == null) return accent;
      if (HSLColor.fromColor(dominant).lightness < 0.15) {
        return accent ?? dominant;
      }
      return dominant;
    } catch (_) {
      return null;
    }
  }

  void updateCoverColor(String? coverPath) {
    // Vide = pochette du NAS alors que les identifiants ne sont pas encore
    // charges (voir SubsonicRefs.resolve).
    if (coverPath == null || coverPath.isEmpty) {
      dominantColor = null;
      _notify();
      return;
    }
    if (_colorCache.containsKey(coverPath)) {
      dominantColor = _colorCache[coverPath];
      _notify();
      return;
    }
    final requestId = ++_lastColorRequest;
    unawaited(_colorFor(coverPath).then((color) {
      if (_disposed || requestId != _lastColorRequest) return;
      // Echec (pochette illisible) : pas de couleur plutot que celle du
      // titre precedent.
      dominantColor = color;
      _notify();
    }));
  }

  final Map<String, Future<Color?>> _pending = {};

  Future<Color?> _colorFor(String coverPath) {
    final cached = _colorCache[coverPath];
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent(coverPath, () async {
      final color = await _extractDominantColor(coverPath);
      unawaited(_pending.remove(coverPath));
      if (color != null) _colorCache[coverPath] = color;
      return color;
    });
  }

  /// Calcule a l'avance la couleur des pochettes des prochains titres (et
  /// charge l'image au passage) : au changement de titre, la couleur est
  /// deja la, sans passer un instant par celle du titre precedent.
  void prefetchCoverColors(Iterable<String?> coverPaths) {
    for (final path in coverPaths) {
      if (path != null && path.isNotEmpty) unawaited(_colorFor(path));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
