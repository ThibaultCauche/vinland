/// Paroles d'un titre : synchronisees (chaque ligne a son instant de debut)
/// ou simples (texte brut, sans minutage).
class LyricLine {
  /// Instant ou la ligne commence. Null pour des paroles non synchronisees.
  final Duration? start;
  final String text;

  const LyricLine(this.text, {this.start});

  @override
  bool operator ==(Object other) =>
      other is LyricLine && other.start == start && other.text == text;

  @override
  int get hashCode => Object.hash(start, text);

  @override
  String toString() => 'LyricLine($start, $text)';
}

class Lyrics {
  final List<LyricLine> lines;

  /// D'ou viennent les paroles (« Navidrome », « LRCLIB ») : affiche sous
  /// les paroles, par honnetete envers la source.
  final String source;

  const Lyrics(this.lines, {required this.source});

  /// Vrai si les lignes ont un minutage (defilement automatique possible).
  bool get isSynced => lines.isNotEmpty && lines.every((l) => l.start != null);

  bool get isEmpty => lines.every((l) => l.text.trim().isEmpty);

  /// Index de la ligne en cours a [position] : la derniere ligne deja
  /// commencee. -1 avant la premiere ligne, ou si les paroles ne sont pas
  /// synchronisees.
  int activeIndex(Duration position) {
    if (!isSynced) return -1;
    // Recherche dichotomique : appele plusieurs fois par seconde.
    var lo = 0, hi = lines.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].start! <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  /// Paroles au format LRC (`[mm:ss.xx] texte`). Une ligne peut porter
  /// plusieurs instants (refrain repete). Les balises d'en-tete (`[ar:...]`,
  /// `[offset:...]`) sont ignorees sauf `offset`, applique en millisecondes
  /// comme le veut le format (positif = paroles plus tot). Sans aucune ligne
  /// minutee, le texte est garde tel quel en paroles simples.
  static Lyrics parseLrc(String raw, {required String source}) {
    final timed = <LyricLine>[];
    final plain = <LyricLine>[];
    var offset = Duration.zero;
    final tag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
    final offsetTag =
        RegExp(r'^\[offset:\s*([+-]?\d+)\]', caseSensitive: false);
    final headerTag = RegExp(r'^\[[a-zA-Z]+:.*\]$');

    for (final rawLine in raw.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      final off = offsetTag.firstMatch(line);
      if (off != null) {
        offset = Duration(milliseconds: int.parse(off.group(1)!));
        continue;
      }
      final matches = tag.allMatches(line).toList();
      if (matches.isEmpty) {
        if (!headerTag.hasMatch(line)) plain.add(LyricLine(line));
        continue;
      }
      // Les instants sont en tete de ligne, le texte suit le dernier.
      final text = line.substring(matches.last.end).trim();
      for (final m in matches) {
        final fraction = m.group(3) ?? '0';
        // .5 = 500 ms, .05 = 50 ms, .005 = 5 ms.
        final ms = int.parse(fraction.padRight(3, '0'));
        timed.add(LyricLine(text,
            start: Duration(
              minutes: int.parse(m.group(1)!),
              seconds: int.parse(m.group(2)!),
              milliseconds: ms,
            )));
      }
    }

    if (timed.isEmpty) {
      return Lyrics(_trimBlank(plain), source: source);
    }
    timed.sort((a, b) => a.start!.compareTo(b.start!));
    return Lyrics([
      for (final l in timed)
        LyricLine(l.text, start: _clamp(l.start! - offset)),
    ], source: source);
  }

  /// Paroles simples a partir d'un texte brut.
  static Lyrics plain(String raw, {required String source}) => Lyrics(
      _trimBlank(
          [for (final l in raw.split(RegExp(r'\r?\n'))) LyricLine(l.trim())]),
      source: source);

  static Duration _clamp(Duration d) => d.isNegative ? Duration.zero : d;

  /// Retire les lignes vides en tete et en fin.
  static List<LyricLine> _trimBlank(List<LyricLine> lines) {
    var start = 0, end = lines.length;
    while (start < end && lines[start].text.isEmpty) {
      start++;
    }
    while (end > start && lines[end - 1].text.isEmpty) {
      end--;
    }
    return lines.sublist(start, end);
  }
}
