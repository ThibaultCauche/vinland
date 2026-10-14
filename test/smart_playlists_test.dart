import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/domain/smart_playlists.dart';
import 'package:vinland/models/track.dart';

final _now = DateTime(2026, 10, 14);

Track _t(
  String id, {
  int plays = 0,
  DateTime? lastPlayed,
  DateTime? added,
  bool liked = false,
  int? year,
  bool placeholder = false,
}) =>
    Track(
      id: id,
      title: 'Titre $id',
      artist: 'Artiste',
      album: 'Album',
      duration: const Duration(minutes: 3),
      filePath: placeholder ? null : '/music/$id.mp3',
      playCount: plays,
      lastPlayed: lastPlayed,
      addedToServerAt: added,
      isLiked: liked,
      year: year,
    );

List<Track> _many(
        String prefix, int n, Track Function(String id, int i) make) =>
    [for (var i = 0; i < n; i++) make('$prefix$i', i)];

SmartPlaylist? _find(List<SmartPlaylist> all, String suffix) {
  for (final p in all) {
    if (p.id == '${SmartPlaylist.idPrefix}$suffix') return p;
  }
  return null;
}

void main() {
  test('bibliotheque vide : aucune playlist', () {
    expect(SmartPlaylist.compute(const [], now: _now), isEmpty);
  });

  test('moins de 5 titres correspondants : playlist non proposee', () {
    final all =
        SmartPlaylist.compute(_many('n', 4, (id, _) => _t(id)), now: _now);
    expect(_find(all, 'never'), isNull);
  });

  test('jamais ecoutes : les plus recemment ajoutes d abord', () {
    final library = [
      ..._many('n', 5,
          (id, i) => _t(id, added: _now.subtract(Duration(days: 100 + i)))),
      _t('ecoute', plays: 1, lastPlayed: _now),
      _t('vide', placeholder: true),
    ];
    final never = _find(SmartPlaylist.compute(library, now: _now), 'never')!;
    expect(never.tracks.map((t) => t.id), ['n0', 'n1', 'n2', 'n3', 'n4']);
  });

  test('ajoutes ce mois-ci : 30 derniers jours seulement', () {
    final library = [
      ..._many('r', 5,
          (id, i) => _t(id, added: _now.subtract(Duration(days: i * 5)))),
      _t('vieux', added: _now.subtract(const Duration(days: 45))),
    ];
    final recent = _find(SmartPlaylist.compute(library, now: _now), 'recent')!;
    expect(recent.tracks.map((t) => t.id), ['r0', 'r1', 'r2', 'r3', 'r4']);
  });

  test('tes classiques : 3 ecoutes minimum, du plus ecoute au moins', () {
    final library = [
      ..._many('c', 5, (id, i) => _t(id, plays: 3 + i, lastPlayed: _now)),
      _t('rare', plays: 2, lastPlayed: _now),
    ];
    final top = _find(SmartPlaylist.compute(library, now: _now), 'top')!;
    expect(top.tracks.map((t) => t.id), ['c4', 'c3', 'c2', 'c1', 'c0']);
  });

  test('likes oublies : likes pas ecoutes depuis 3 mois, jamais ecoutes inclus',
      () {
    final library = [
      ..._many(
          'l',
          4,
          (id, i) => _t(id,
              liked: true,
              plays: 1,
              lastPlayed: _now.subtract(Duration(days: 100 + i)))),
      _t('jamais', liked: true),
      _t('recent', liked: true, plays: 1, lastPlayed: _now),
      _t('pas-like',
          plays: 1, lastPlayed: _now.subtract(const Duration(days: 200))),
    ];
    final forgotten =
        _find(SmartPlaylist.compute(library, now: _now), 'forgotten-likes')!;
    expect(forgotten.tracks.map((t) => t.id).toSet(),
        {'l0', 'l1', 'l2', 'l3', 'jamais'});
    // Le plus longtemps oublie d'abord.
    expect(forgotten.tracks.first.id, 'jamais');
  });

  test('a redecouvrir : souvent ecoutes mais plus depuis 6 mois', () {
    final old = _now.subtract(const Duration(days: 200));
    final library = [
      ..._many('x', 5, (id, i) => _t(id, plays: 5 + i, lastPlayed: old)),
      _t('peu', plays: 2, lastPlayed: old),
      _t('encore', plays: 20, lastPlayed: _now),
    ];
    final again =
        _find(SmartPlaylist.compute(library, now: _now), 'rediscover')!;
    expect(again.tracks.map((t) => t.id), ['x4', 'x3', 'x2', 'x1', 'x0']);
  });

  test('decennies : une playlist par decennie assez fournie, dans l ordre', () {
    final library = [
      ..._many('a', 5, (id, i) => _t(id, year: 1985 + i)),
      ..._many('b', 6, (id, i) => _t(id, year: 2003)),
      ..._many('c', 2, (id, i) => _t(id, year: 1972)),
      _t('sans-annee'),
    ];
    final all = SmartPlaylist.compute(library, now: _now);
    final decades =
        all.where((p) => p.id.contains('decade')).map((p) => p.name).toList();
    expect(decades, ['Années 80', 'Années 2000']);
  });

  test('libelles des decennies', () {
    expect(SmartPlaylist.decadeLabel(1960), 'Années 60');
    expect(SmartPlaylist.decadeLabel(2010), 'Années 2010');
  });

  test('une liste est coupee a 200 titres', () {
    final library = _many('n', 250, (id, _) => _t(id));
    final never = _find(SmartPlaylist.compute(library, now: _now), 'never')!;
    expect(never.tracks, hasLength(SmartPlaylist.maxTracks));
  });

  test('toPlaylist garde l ordre et l id intelligent', () {
    final library = _many('c', 5, (id, i) => _t(id, plays: 10 - i));
    final top = _find(SmartPlaylist.compute(library, now: _now), 'top')!;
    final playlist = top.toPlaylist();
    expect(playlist.id, startsWith(SmartPlaylist.idPrefix));
    expect(playlist.trackIds, ['c0', 'c1', 'c2', 'c3', 'c4']);
  });
}
