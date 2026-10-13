import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinland/desktop/desktop_theme.dart';
import 'package:vinland/services/subsonic_refs.dart';
import 'package:vinland/theme/mobile_theme.dart';
import 'package:vinland/theme/solid_color_effect.dart';
import 'package:vinland/theme/theme_controller.dart';

/// Les reglages d'apparence (Parametres > Apparence) doivent survivre a un
/// redemarrage, et la pochette epinglee ne doit jamais garder de jeton.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SubsonicRefs.coverUrlBuilder = null;
  });

  test('sans reglage enregistre : valeurs par defaut', () async {
    final theme = ThemeController();
    await theme.load();
    expect(theme.desktopThemeMode, DesktopThemeMode.solid);
    expect(theme.mobileThemeMode, MobileThemeMode.solid);
    expect(theme.desktopThemeColor, DesktopTheme.defaultColor);
    expect(theme.mobileThemeColor, MobileTheme.defaultColor);
    expect(theme.desktopSolidEffect, SolidColorEffect.flat);
    expect(theme.mobilePinnedCoverPath, isNull);
  });

  test('les reglages changes sont retrouves au lancement suivant', () async {
    final before = ThemeController();
    var notified = 0;
    before.addListener(() => notified++);
    await before.setDesktopThemeMode(DesktopThemeMode.coverBlur);
    await before.setDesktopThemeColor(const Color(0xFF112233));
    await before.setDesktopCoverBlurSigma(12);
    await before.setDesktopSolidEffect(SolidColorEffect.metal);
    await before.setMobileThemeMode(MobileThemeMode.coverBlur);
    await before.setMobileThemeColor(const Color(0xFF445566));
    await before.setMobileCoverBlurSigma(7);
    await before.setMobileSolidEffect(SolidColorEffect.pastel);
    expect(notified, 8);

    final after = ThemeController();
    await after.load();
    expect(after.desktopThemeMode, DesktopThemeMode.coverBlur);
    expect(after.desktopThemeColor, const Color(0xFF112233));
    expect(after.desktopCoverBlurSigma, 12);
    expect(after.desktopSolidEffect, SolidColorEffect.metal);
    expect(after.mobileThemeMode, MobileThemeMode.coverBlur);
    expect(after.mobileThemeColor, const Color(0xFF445566));
    expect(after.mobileCoverBlurSigma, 7);
    expect(after.mobileSolidEffect, SolidColorEffect.pastel);
  });

  test(
      'une pochette epinglee avant la 1.3 (URL avec jeton) est reecrite '
      'sans jeton au demarrage', () async {
    const legacy =
        'https://nas.example/rest/getCoverArt.view?id=abc&u=moi&t=jeton&s=sel';
    SharedPreferences.setMockInitialValues({
      'vinland_mobile_pinned_cover': legacy,
      'vinland_desktop_pinned_cover': legacy,
    });
    SubsonicRefs.coverUrlBuilder = (id) => 'https://nas.example/cover/$id';

    await ThemeController().load();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('vinland_mobile_pinned_cover'),
        SubsonicRefs.cover('abc'));
    expect(prefs.getString('vinland_desktop_pinned_cover'),
        SubsonicRefs.cover('abc'));

    final theme = ThemeController();
    await theme.load();
    expect(theme.mobilePinnedCoverPath, 'https://nas.example/cover/abc');
    expect(theme.desktopPinnedCoverPath, 'https://nas.example/cover/abc');
  });

  test('epingler puis desepingler une pochette', () async {
    final theme = ThemeController();
    await theme.setMobilePinnedCoverPath(
        'https://nas.example/rest/getCoverArt.view?id=9&t=jeton&s=sel');
    await theme.setDesktopPinnedCoverPath('/local/cover.jpg');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('vinland_mobile_pinned_cover'),
        SubsonicRefs.cover('9'));
    expect(theme.desktopPinnedCoverPath, '/local/cover.jpg');

    await theme.setMobilePinnedCoverPath(null);
    expect(prefs.getString('vinland_mobile_pinned_cover'), isNull);
  });

  test('sans pochette, la couleur d\'ambiance est effacee', () {
    final theme = ThemeController()..dominantColor = Colors.red;
    theme.updateCoverColor(null);
    expect(theme.dominantColor, isNull);
    theme.dispose();
  });
}
