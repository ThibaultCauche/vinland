import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'cover_picker.dart';
import 'mobile_theme.dart';
import 'solid_color_effect.dart';

/// Equivalent mobile de DesktopThemeSettingsSection (lib/desktop/) : meme
/// choix Uni / Cover floutee, sans le mode "Transparent" -- une app mobile
/// est toujours plein ecran, il n'y a rien de systeme a voir a travers.
class MobileThemeSettingsSection extends StatelessWidget {
  const MobileThemeSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AppState,
        (MobileThemeMode, Color, double, SolidColorEffect, String?)>(
      selector: (_, state) => (
        state.mobileThemeMode,
        state.mobileThemeColor,
        state.mobileCoverBlurSigma,
        state.mobileSolidEffect,
        state.mobilePinnedCoverPath,
      ),
      builder: (context, data, __) {
        final (mode, color, blurSigma, effect, pinnedCoverPath) = data;
        final state = context.read<AppState>();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _ThemeOption(
                    label: 'Uni',
                    icon: Icons.square_rounded,
                    iconColor: color,
                    selected: mode == MobileThemeMode.solid,
                    onTap: () =>
                        state.setMobileThemeMode(MobileThemeMode.solid),
                  ),
                  const SizedBox(width: 12),
                  _ThemeOption(
                    label: 'Cover floutee',
                    icon: Icons.blur_on,
                    selected: mode == MobileThemeMode.coverBlur,
                    onTap: () =>
                        state.setMobileThemeMode(MobileThemeMode.coverBlur),
                  ),
                ],
              ),
            ),
            if (mode == MobileThemeMode.solid)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _SolidColorSection(
                  color: color,
                  onChanged: (c) => state.setMobileThemeColor(c),
                  effect: effect,
                  onEffectChanged: (e) => state.setMobileSolidEffect(e),
                ),
              ),
            if (mode == MobileThemeMode.coverBlur) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _BlurSigmaSection(
                  sigma: blurSigma,
                  onChanged: (v) => state.setMobileCoverBlurSigma(v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: PinnedCoverSection(
                  pinnedCoverPath: pinnedCoverPath,
                  currentTrackCoverPath: state.currentTrack?.coverPath,
                  albums: state.albums,
                  onChanged: (path) => state.setMobilePinnedCoverPath(path),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SolidColorSection extends StatelessWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  final SolidColorEffect effect;
  final ValueChanged<SolidColorEffect> onEffectChanged;
  const _SolidColorSection({
    required this.color,
    required this.onChanged,
    required this.effect,
    required this.onEffectChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Effet',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: SolidColorEffect.values.map((e) {
            final selected = e == effect;
            return GestureDetector(
              onTap: () => onEffectChanged(e),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            selected ? const Color(0xFF1DB954) : Colors.white24,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: SolidEffectBackground(
                      color: color,
                      effect: e,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(e.label,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white54,
                        fontSize: 11,
                      )),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        const Text('Couleurs preenregistrees',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: MobileTheme.presetColors.map((preset) {
            final selected = preset.toARGB32() == color.toARGB32();
            return GestureDetector(
              onTap: () => onChanged(preset),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: preset,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          selected ? const Color(0xFF1DB954) : Colors.white24,
                      width: selected ? 2 : 1,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        const Text('Couleur personnalisee',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        ColorPicker(
          pickerColor: color,
          onColorChanged: onChanged,
          enableAlpha: false,
          displayThumbColor: true,
          paletteType: PaletteType.hsv,
          pickerAreaHeightPercent: 0.6,
        ),
      ],
    );
  }
}

class _BlurSigmaSection extends StatelessWidget {
  final double sigma;
  final ValueChanged<double> onChanged;
  const _BlurSigmaSection({required this.sigma, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Intensite du flou',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        Row(
          children: [
            const Icon(Icons.blur_off, color: Colors.white38, size: 18),
            Expanded(
              child: Slider(
                value: sigma,
                min: 10,
                max: 150,
                activeColor: const Color(0xFF1DB954),
                inactiveColor: Colors.white12,
                onChanged: onChanged,
              ),
            ),
            const Icon(Icons.blur_on, color: Colors.white38, size: 18),
          ],
        ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? iconColor;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.icon,
    this.iconColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF1DB954) : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: iconColor ?? Colors.white70, size: 24),
              const SizedBox(height: 6),
              Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
