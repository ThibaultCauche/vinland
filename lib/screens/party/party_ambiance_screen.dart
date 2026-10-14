import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:window_manager/window_manager.dart';

import '../../controllers/party_controller.dart';
import '../../services/party/party_link.dart';
import 'blind_test_view.dart';
import 'party_widgets.dart';

/// Deux couleurs tirees d'une pochette (fond et accent).
typedef AmbianceColors = ({Color background, Color accent});

const AmbianceColors _defaultColors =
    (background: Color(0xFF1A1A2E), accent: partyAccent);

/// Extrait les couleurs d'une pochette avec PaletteGenerator (deja utilise
/// pour la couleur d'ambiance du lecteur, voir ThemeController).
Future<AmbianceColors?> loadAmbianceColors(ImageProvider image) async {
  final palette = await PaletteGenerator.fromImageProvider(
    image,
    size: const Size(120, 120),
    maximumColorCount: 12,
  );
  final background = palette.darkMutedColor?.color ??
      palette.darkVibrantColor?.color ??
      palette.dominantColor?.color;
  final accent = palette.vibrantColor?.color ??
      palette.lightVibrantColor?.color ??
      palette.dominantColor?.color;
  if (background == null || accent == null) return null;
  return (background: background, accent: accent);
}

/// Plein ecran : la fenetre entiere sur Windows (le PC branche a la
/// tele), le mode immersif sur telephone.
Future<void> setAmbianceFullscreen(bool on) async {
  try {
    if (!kIsWeb && Platform.isWindows) {
      await windowManager.setFullScreen(on);
    } else {
      await SystemChrome.setEnabledSystemUIMode(
          on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  } catch (e) {
    debugPrint('setAmbianceFullscreen error: $e');
  }
}

void openPartyAmbiance(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => const PartyAmbianceScreen()));

/// Ecran d'ambiance pour la tele de la soiree : grande pochette sur un fond
/// aux couleurs de la pochette, titre, qui l'a propose, les 3 suivants et
/// le QR code pour rejoindre. Rien a toucher : il suit la soiree tout seul.
/// Echap ou le bouton en haut a droite pour sortir, F pour le plein ecran.
class PartyAmbianceScreen extends StatefulWidget {
  const PartyAmbianceScreen({
    super.key,
    this.colorsFor = loadAmbianceColors,
    this.setFullscreen = setAmbianceFullscreen,
  });

  final Future<AmbianceColors?> Function(ImageProvider image) colorsFor;
  final Future<void> Function(bool on) setFullscreen;

  @override
  State<PartyAmbianceScreen> createState() => _PartyAmbianceScreenState();
}

class _PartyAmbianceScreenState extends State<PartyAmbianceScreen> {
  final _focus = FocusNode();
  bool _fullscreen = true;
  String? _coverId;
  AmbianceColors _colors = _defaultColors;

  @override
  void initState() {
    super.initState();
    widget.setFullscreen(true);
  }

  @override
  void dispose() {
    if (_fullscreen) widget.setFullscreen(false);
    _focus.dispose();
    super.dispose();
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    widget.setFullscreen(_fullscreen);
  }

  /// Recalcule les couleurs quand la pochette change (une fois par titre).
  void _updateColors(PartyController party) {
    final coverId = party.nowPlaying?.coverId;
    if (coverId == _coverId) return;
    _coverId = coverId;
    final image = partyCoverImage(party, coverId, 300);
    if (image == null) {
      _colors = _defaultColors;
      return;
    }
    widget.colorsFor(image).then((colors) {
      if (!mounted || _coverId != coverId) return;
      setState(() => _colors = colors ?? _defaultColors);
    }, onError: (Object e) {
      // Pochette injoignable : on garde les couleurs d'avant.
      debugPrint('ambiance colors error: $e');
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF ||
        event.logicalKey == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final party = context.watch<PartyController>();
    _updateColors(party);
    final relay = party.relayUrl, code = party.code;
    final invite = relay != null && code != null && party.isActive
        ? PartyInvite(relayUrl: relay, code: code)
        : null;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 1200),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _colors.background,
                Color.lerp(_colors.background, Colors.black, 0.6)!,
              ],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: LayoutBuilder(
                      builder: (context, box) => party.blindTest != null
                          ? SingleChildScrollView(
                              child: BlindTestAmbiance(
                                state: party.blindTest!,
                                scale: (box.maxHeight / 700).clamp(0.6, 2.0),
                              ),
                            )
                          : box.maxWidth > box.maxHeight
                              ? _wide(party, box, invite)
                              : _tall(party, box, invite),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: _fullscreen
                            ? 'Quitter le plein écran'
                            : 'Plein écran',
                        icon: Icon(
                            _fullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                            color: Colors.white38),
                        onPressed: _toggleFullscreen,
                      ),
                      IconButton(
                        tooltip: 'Fermer',
                        icon: const Icon(Icons.close, color: Colors.white38),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tele ou ecran de PC : pochette a gauche, le reste a droite.
  Widget _wide(PartyController party, BoxConstraints box, PartyInvite? invite) {
    final cover = (box.maxHeight * 0.8).clamp(120.0, box.maxWidth * 0.45);
    return Row(
      children: [
        _bigCover(party, cover),
        SizedBox(width: box.maxWidth * 0.04),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _nowPlaying(party, scale: box.maxHeight / 700),
              const SizedBox(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _upNext(party)),
                  if (invite != null) ...[
                    const SizedBox(width: 24),
                    _qr(invite, (box.maxHeight * 0.25).clamp(96.0, 220.0)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Telephone ou tablette en portrait.
  Widget _tall(PartyController party, BoxConstraints box, PartyInvite? invite) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _bigCover(party, box.maxWidth * 0.8)),
          const SizedBox(height: 24),
          _nowPlaying(party, scale: box.maxWidth / 500),
          const SizedBox(height: 24),
          _upNext(party),
          if (invite != null) ...[
            const SizedBox(height: 24),
            Center(child: _qr(invite, 140)),
          ],
        ],
      ),
    );
  }

  Widget _bigCover(PartyController party, double size) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _colors.accent.withValues(alpha: 0.35),
              blurRadius: 60,
              spreadRadius: 4,
            ),
          ],
        ),
        child: PartyCover(
          key: const ValueKey('ambiance-cover'),
          coverId: party.nowPlaying?.coverId,
          size: size,
          radius: 16,
        ),
      );

  Widget _nowPlaying(PartyController party, {required double scale}) {
    final song = party.nowPlaying;
    final s = scale.clamp(0.6, 2.0);
    final by = byLabel(party.nowPlayingBy);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          party.partyName.isEmpty
              ? 'EN CE MOMENT'
              : party.partyName.toUpperCase(),
          style: TextStyle(
            color: _colors.accent,
            fontSize: 16 * s,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          song?.title ?? 'La musique arrive…',
          key: const ValueKey('ambiance-title'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 48 * s,
            fontWeight: FontWeight.bold,
            height: 1.1,
          ),
        ),
        if (song != null && song.artist.isNotEmpty)
          Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white70, fontSize: 28 * s),
          ),
        if (song != null && by != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _colors.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              by,
              key: const ValueKey('ambiance-by'),
              style: TextStyle(color: Colors.white, fontSize: 18 * s),
            ),
          ),
        ],
      ],
    );
  }

  /// « Proposé par Léa », « Choisi par la radio », rien pour l'hote.
  static String? byLabel(String by) => switch (by) {
        '' => null,
        'Radio' => 'Choisi par la radio',
        _ => 'Proposé par $by',
      };

  Widget _upNext(PartyController party) {
    final next = party.queue.items.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('À SUIVRE',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2)),
        const SizedBox(height: 8),
        if (next.isEmpty)
          const Text('Propose un titre avec ton téléphone !',
              style: TextStyle(color: Colors.white70, fontSize: 18)),
        for (final item in next)
          Padding(
            key: ValueKey('ambiance-next-${item.id}'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                PartyCover(coverId: item.song.coverId, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${item.song.title} · ${item.song.artist}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 8),
                Text(item.by,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 16)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _qr(PartyInvite invite, double size) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: invite.toString(),
              size: size,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
            ),
            const SizedBox(height: 6),
            Text(
              invite.code,
              key: const ValueKey('ambiance-code'),
              style: const TextStyle(
                color: Colors.black,
                fontSize: 20,
                letterSpacing: 4,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
}
