import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/solid_color_effect.dart';

/// Fond de la fenetre desktop, choisi par l'utilisateur (Parametres > Apparence) :
/// - solid : couleur unie fixe (choisie via une palette RGB), fiable sur
///   toutes les machines, comme Spotify.
/// - coverBlur : la cover du titre en cours, tres floutee et assombrie
///   (le rendu d'origine de l'app, avant les essais de transparence).
/// - transparent : la fenetre elle-meme devient transparente pour voir
///   litteralement ce qu'il y a derriere. Experimental : sur ce Windows en
///   particulier (build 26200), transparent/acrylic/mica se sont tous les
///   trois rendus en un aplat noir opaque au lieu du bon effet -- probleme du
///   package flutter_acrylic sur ce build, pas quelque chose que ce code
///   peut corriger. Laisse en option puisque ca peut fonctionner ailleurs.
enum DesktopThemeMode { solid, coverBlur, transparent }

class DesktopTheme {
  static const _keyMode = 'vinland_desktop_theme_mode';
  static const _keyColor = 'vinland_desktop_theme_color';
  static const _keyBlurSigma = 'vinland_desktop_cover_blur_sigma';
  static const _keySolidEffect = 'vinland_desktop_solid_effect';
  static const _keyPinnedCover = 'vinland_desktop_pinned_cover';
  static const defaultColor = Color(0xFF121212);
  static const defaultBlurSigma = 90.0;

  /// Quelques couleurs de depart pour ne pas laisser l'utilisateur devant
  /// une page blanche : noir Spotify (defaut), puis quelques teintes sombres
  /// qui restent lisibles avec le texte blanc de l'app.
  static const presetColors = [
    Color(0xFF121212),
    Color(0xFF000000),
    Color(0xFF1A1A2E),
    Color(0xFF2B1B3D),
    Color(0xFF1B2A4A),
    Color(0xFF1B3A2A),
    Color(0xFF3A1B1B),
    Color(0xFF2E2E2E),
  ];

  static Future<double> loadBlurSigma() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyBlurSigma) ?? defaultBlurSigma;
  }

  static Future<void> saveBlurSigma(double sigma) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyBlurSigma, sigma);
  }

  static Future<SolidColorEffect> loadSolidEffect() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keySolidEffect);
    return SolidColorEffect.values
        .firstWhere((e) => e.name == name, orElse: () => SolidColorEffect.flat);
  }

  static Future<void> saveSolidEffect(SolidColorEffect effect) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySolidEffect, effect.name);
  }

  /// Cover fixee comme fond du theme "Cover floutee" (Parametres >
  /// Personnalisation), au lieu de suivre le titre en cours de lecture.
  /// Null = comportement par defaut (dynamique, suit la lecture).
  static Future<String?> loadPinnedCover() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPinnedCover);
  }

  static Future<void> savePinnedCover(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_keyPinnedCover);
    } else {
      await prefs.setString(_keyPinnedCover, path);
    }
  }

  static Future<DesktopThemeMode> loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyMode);
    return DesktopThemeMode.values.firstWhere((m) => m.name == name,
        orElse: () => DesktopThemeMode.solid);
  }

  static Future<Color> loadColor() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_keyColor);
    return value != null ? Color(value) : defaultColor;
  }

  static Future<void> saveMode(DesktopThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, mode.name);
    await applyWindowEffect(mode);
  }

  static Future<void> saveColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyColor, color.toARGB32());
  }

  /// La fenetre native ne doit rester transparente que pour le theme
  /// "transparent" : sinon on la desactive explicitement pour repartir d'une
  /// fenetre normale (sinon un reste de transparence pourrait trainer en
  /// changeant de theme).
  static Future<void> applyWindowEffect(DesktopThemeMode mode) async {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    if (mode == DesktopThemeMode.transparent) {
      await acrylic.Window.setEffect(
        effect: acrylic.WindowEffect.transparent,
        color: Colors.transparent,
      );
    } else {
      await acrylic.Window.setEffect(effect: acrylic.WindowEffect.disabled);
    }
  }
}
