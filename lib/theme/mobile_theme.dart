import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'solid_color_effect.dart';

/// Fond des ecrans mobile, choisi par l'utilisateur (Parametres >
/// Personnalisation) : equivalent mobile de DesktopTheme (lib/desktop/), sans
/// le mode "transparent" -- une app mobile est toujours plein ecran, il n'y a
/// rien de systeme a voir derriere.
enum MobileThemeMode { solid, coverBlur }

class MobileTheme {
  static const _keyMode = 'vinland_mobile_theme_mode';
  static const _keyColor = 'vinland_mobile_theme_color';
  static const _keyBlurSigma = 'vinland_mobile_cover_blur_sigma';
  static const _keySolidEffect = 'vinland_mobile_solid_effect';
  static const _keyPinnedCover = 'vinland_mobile_pinned_cover';
  static const defaultColor = Color(0xFF121212);
  static const defaultBlurSigma = 90.0;

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

  static Future<MobileThemeMode> loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_keyMode);
    return MobileThemeMode.values
        .firstWhere((m) => m.name == name, orElse: () => MobileThemeMode.solid);
  }

  static Future<Color> loadColor() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_keyColor);
    return value != null ? Color(value) : defaultColor;
  }

  static Future<double> loadBlurSigma() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyBlurSigma) ?? defaultBlurSigma;
  }

  static Future<void> saveMode(MobileThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, mode.name);
  }

  static Future<void> saveColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyColor, color.toARGB32());
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
}
