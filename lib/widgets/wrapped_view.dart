import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/listening_stats.dart';
import '../models/track.dart';
import '../providers/app_state.dart';
import 'cover_image.dart';

/// Bilan d'ecoute (« Wrapped ») : une annee du journal d'ecoute, ou
/// « Depuis toujours » a partir des compteurs de la bibliotheque. Partage
/// par l'ecran mobile (WrappedScreen) et la vue PC.
class WrappedView extends StatefulWidget {
  const WrappedView({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsets padding;

  @override
  State<WrappedView> createState() => _WrappedViewState();
}

/// Choix « Depuis toujours » dans la liste des periodes.
const _allTime = 0;

class _WrappedViewState extends State<WrappedView> {
  late final Future<List<PlayEvent>> _history =
      context.read<AppState>().listeningHistory();
  int? _period;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlayEvent>>(
      future: _history,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.white54));
        }
        final events = snap.data ?? const <PlayEvent>[];
        final years = ListeningStats.yearsOf(events);
        final period = _period ?? (years.isNotEmpty ? years.first : _allTime);
        final library = context.read<AppState>().allTracks;
        final stats = period == _allTime
            ? ListeningStats.allTime(library)
            : ListeningStats.forYear(events, period);

        return ListView(
          padding: widget.padding,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final y in years) _periodChip('$y', y, period),
                _periodChip('Depuis toujours', _allTime, period),
              ],
            ),
            const SizedBox(height: 16),
            if (stats.isEmpty)
              const _Card(
                colors: [Color(0xFF3A3A3A), Color(0xFF1E1E1E)],
                child: Text(
                  'Pas encore assez d\'écoutes pour un bilan. Lance quelques '
                  'titres et reviens voir !',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              )
            else
              ..._sections(context, stats, library),
          ],
        );
      },
    );
  }

  Widget _periodChip(String label, int value, int selected) => ChoiceChip(
        label: Text(label),
        selected: value == selected,
        onSelected: (_) => setState(() => _period = value),
        labelStyle: TextStyle(
            color: value == selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.w600),
        selectedColor: Colors.white,
        backgroundColor: const Color(0xFF2A2A2A),
        side: BorderSide.none,
        showCheckmark: false,
      );

  List<Widget> _sections(
      BuildContext context, ListeningStats stats, List<Track> library) {
    final byId = {for (final t in library) t.id: t};
    final hours = stats.listened.inMinutes ~/ 60;
    final minutes = stats.listened.inMinutes;
    final title =
        stats.isEstimate ? 'Depuis toujours' : 'Ton année ${stats.label}';
    final topTracksInLibrary = [
      for (final r in stats.topTracks)
        if (r.trackId != null && byId[r.trackId] != null) byId[r.trackId]!
    ];

    return [
      _Card(
        colors: const [Color(0xFF1DB954), Color(0xFF0B5D2A)],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Text(_thousands(minutes),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    height: 1)),
            Text(
                'minutes de musique${hours >= 2 ? ', soit environ $hours heures' : ''}',
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 16),
            Text(
              '${_thousands(stats.plays)} écoutes · '
              '${stats.distinctTracks} titres · '
              '${stats.distinctArtists} artistes',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (topTracksInLibrary.isNotEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black),
                onPressed: () => context.read<AppState>().playTrack(
                    topTracksInLibrary.first,
                    trackList: topTracksInLibrary),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Écouter ton top'),
              ),
            ],
          ],
        ),
      ),
      if (stats.topArtists.isNotEmpty)
        _Card(
          colors: const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
          child: _ranking(
            heading: 'Ton artiste n°1',
            highlight: stats.topArtists.first.name,
            items: stats.topArtists,
          ),
        ),
      if (stats.topTracks.isNotEmpty)
        _Card(
          colors: const [Color(0xFFFF512F), Color(0xFFB0244B)],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tes titres les plus écoutés',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 12),
              for (final (i, r) in stats.topTracks.indexed)
                _TrackRankRow(
                  rank: i + 1,
                  item: r,
                  coverPath: byId[r.trackId]?.coverPath,
                ),
            ],
          ),
        ),
      if (stats.topAlbums.isNotEmpty)
        _Card(
          colors: const [Color(0xFF0F2027), Color(0xFF2C5364)],
          child: _ranking(
            heading: 'Tes albums',
            items: stats.topAlbums,
          ),
        ),
      if (stats.topGenres.isNotEmpty)
        _Card(
          colors: const [Color(0xFFF7971E), Color(0xFFB8620B)],
          child: _ranking(
            heading: 'Ton genre',
            highlight: stats.topGenres.first.name,
            items: stats.topGenres,
          ),
        ),
      if (stats.busiestMonth != null || stats.firstPlay != null)
        _Card(
          colors: const [Color(0xFF283C86), Color(0xFF45A247)],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Moments forts',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 12),
              if (stats.busiestMonth case (final month, final plays))
                _fact(
                    Icons.calendar_month,
                    'Ton mois le plus musical : ${_months[month - 1]}',
                    '$plays écoutes'),
              if (stats.busiestDay case (final day, final plays))
                _fact(
                    Icons.local_fire_department,
                    'Ton jour record : ${day.day} ${_months[day.month - 1]}',
                    '$plays écoutes ce jour-là'),
              if (stats.firstPlay case final first?)
                _fact(Icons.flag, 'Premier titre de l\'année : ${first.title}',
                    first.artist),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
        child: Text(
          stats.isEstimate
              ? 'Calculé à partir du nombre d\'écoutes de chaque titre encore '
                  'dans ta bibliothèque.'
              : 'Calculé à partir des écoutes faites sur cet appareil.',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ),
    ];
  }

  Widget _ranking({
    required String heading,
    String? highlight,
    required List<Ranked> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading,
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
        if (highlight != null) ...[
          const SizedBox(height: 4),
          Text(highlight,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900)),
        ],
        const SizedBox(height: 12),
        for (final (i, r) in items.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.w800)),
                ),
                Expanded(
                  child: Text(
                    r.subtitle == null ? r.name : '${r.name} · ${r.subtitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
                Text('${r.plays}',
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _fact(IconData icon, String title, String subtitle) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  Text(subtitle, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      );

  static const _months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  /// 12345 -> « 12 345 ».
  static String _thousands(int n) {
    final s = '$n';
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(' ');
      out.write(s[i]);
    }
    return out.toString();
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.colors, required this.child});

  final List<Color> colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: child,
    );
  }
}

class _TrackRankRow extends StatelessWidget {
  const _TrackRankRow({
    required this.rank,
    required this.item,
    required this.coverPath,
  });

  final int rank;
  final Ranked item;
  final String? coverPath;

  @override
  Widget build(BuildContext context) {
    final path = coverPath;
    final hasCover = path != null && context.read<AppState>().coverExists(path);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('$rank',
                style: const TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w800)),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 44,
              height: 44,
              color: Colors.black26,
              child: hasCover
                  ? Image(
                      image: coverImageProvider(context,
                          path: path, width: 44, height: 44),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    )
                  : const Icon(Icons.music_note, color: Colors.white54),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                if (item.subtitle != null)
                  Text(item.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          Text('${item.plays}', style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
