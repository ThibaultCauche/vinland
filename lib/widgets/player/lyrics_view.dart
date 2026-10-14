import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/lyrics.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';

/// Paroles du titre en cours, partagees par l'ecran mobile (LyricsScreen) et
/// le panneau PC. Synchronisees : la ligne en cours est mise en avant et
/// reste au tiers haut de la zone, un tap sur une ligne y saute. Simples :
/// texte qui defile a la main.
class LyricsView extends StatelessWidget {
  const LyricsView({super.key, this.textAlign = TextAlign.left});

  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, Track?>(
      selector: (_, state) => state.displayTrack,
      builder: (context, track, _) {
        if (track == null) {
          return const _LyricsMessage('Rien en cours de lecture');
        }
        return FutureBuilder<Lyrics?>(
          // La cle relance la recherche a chaque changement de titre.
          key: ValueKey(track.id),
          future: context.read<AppState>().lyrics.lyricsFor(track),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white54),
              );
            }
            final lyrics = snap.data;
            if (lyrics == null || lyrics.isEmpty) {
              return const _LyricsMessage(
                  'Pas de paroles trouvées pour ce titre');
            }
            return _LyricsLines(
              key: ValueKey('lines-${track.id}'),
              lyrics: lyrics,
              textAlign: textAlign,
            );
          },
        );
      },
    );
  }
}

class _LyricsMessage extends StatelessWidget {
  const _LyricsMessage(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 15)),
      );
}

class _LyricsLines extends StatefulWidget {
  const _LyricsLines({
    super.key,
    required this.lyrics,
    required this.textAlign,
  });

  final Lyrics lyrics;
  final TextAlign textAlign;

  @override
  State<_LyricsLines> createState() => _LyricsLinesState();
}

class _LyricsLinesState extends State<_LyricsLines> {
  final _scroll = ScrollController();
  late final List<GlobalKey> _keys =
      List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
  Timer? _ticker;
  int _active = -1;

  /// Faux apres un defilement a la main : on laisse l'utilisateur lire ou
  /// il veut, le suivi reprend au tap sur une ligne ou au bouton.
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    if (widget.lyrics.isSynced) {
      _ticker = Timer.periodic(
          const Duration(milliseconds: 200), (_) => _refreshActive());
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshActive());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Meme source que PlayerSlider : le moteur audio local, sauf en synchro
  /// perso participant ou rien ne joue ici (position recue de l'hote).
  Duration get _position {
    final state = context.read<AppState>();
    return state.isPersonalSyncParticipant
        ? state.displayPosition
        : state.player.position;
  }

  void _refreshActive() {
    if (!mounted) return;
    final index = widget.lyrics.activeIndex(_position);
    if (index == _active) return;
    setState(() => _active = index);
    if (_follow) _scrollTo(index);
  }

  void _scrollTo(int index) {
    if (index < 0 || index >= _keys.length) return;
    final ctx = _keys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic);
  }

  void _resumeFollow() {
    setState(() => _follow = true);
    _scrollTo(_active);
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;
    final synced = lyrics.isSynced;
    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (_) {
            if (synced && _follow) setState(() => _follow = false);
            return false;
          },
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              crossAxisAlignment: widget.textAlign == TextAlign.center
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lyrics.lines.length; i++) _line(context, i),
                const SizedBox(height: 24),
                Text('Paroles : ${lyrics.source}',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ),
        if (synced && !_follow)
          Positioned(
            right: 8,
            bottom: 8,
            child: FloatingActionButton.small(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              tooltip: 'Suivre la lecture',
              onPressed: _resumeFollow,
              child: const Icon(Icons.my_location),
            ),
          ),
      ],
    );
  }

  Widget _line(BuildContext context, int i) {
    final line = widget.lyrics.lines[i];
    final synced = widget.lyrics.isSynced;
    final isActive = i == _active;
    final isPast = synced && i < _active;
    final text = Text(
      line.text.isEmpty ? '♪' : line.text,
      key: _keys[i],
      textAlign: widget.textAlign,
      style: TextStyle(
        color: !synced || isActive
            ? Colors.white
            : (isPast ? Colors.white38 : Colors.white60),
        fontSize: synced ? 22 : 17,
        height: 1.3,
        fontWeight: synced ? FontWeight.w700 : FontWeight.w500,
      ),
    );
    final padded = Padding(
      padding: EdgeInsets.symmetric(vertical: synced ? 8 : 3),
      child: AnimatedScale(
        scale: isActive ? 1.04 : 1,
        duration: const Duration(milliseconds: 200),
        alignment: widget.textAlign == TextAlign.center
            ? Alignment.center
            : Alignment.centerLeft,
        child: text,
      ),
    );
    if (!synced) return padded;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        context.read<AppState>().seek(line.start!);
        setState(() => _follow = true);
      },
      child: padded,
    );
  }
}
