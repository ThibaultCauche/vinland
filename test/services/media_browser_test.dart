import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/media_browser.dart';

Track _t(String id, {String? file = '/music/x.mp3'}) => Track(
      id: id,
      title: 'Titre $id',
      artist: 'Artiste',
      album: 'Album',
      duration: const Duration(minutes: 3),
      filePath: file,
    );

void main() {
  late List<(Track, List<Track>)> played;
  late VinlandMediaBrowser browser;
  final liked = [_t('a'), _t('b')];
  final weekly = [_t('c')];
  final all = [...liked, ...weekly, _t('fantome', file: null)];
  final playlist = (id: 'p1', title: 'Route', tracks: [_t('b'), _t('c')]);
  final album = (id: 'al1', title: 'Nouvel album', tracks: [_t('d')]);

  setUp(() {
    played = [];
    browser = VinlandMediaBrowser(
      likedTracks: () => liked,
      weeklyTracks: () => weekly,
      allTracks: () => all,
      playlists: () => [playlist],
      newAlbums: () => [album],
      currentTrack: () => weekly.first,
      play: (track, list) async => played.add((track, list)),
      search: (q) => all.where((t) => t.id == q).toList(),
    );
  });

  test('la racine propose les dossiers et un aleatoire lancable', () async {
    final root = await browser.children(AudioService.browsableRootId);
    expect(root.map((i) => i.id), [
      'liked',
      'weekly',
      'shuffle',
      'playlists',
      'albums',
    ]);
    expect(root.firstWhere((i) => i.id == 'shuffle').playable, isTrue);
    expect(root.firstWhere((i) => i.id == 'liked').playable, isFalse);
  });

  test('une playlist liste ses titres, lancables dans leur liste', () async {
    final folders = await browser.children('playlists');
    expect(folders.single.id, 'playlist:p1');
    expect(folders.single.title, 'Route');

    final items = await browser.children('playlist:p1');
    expect(
        items.map((i) => i.id), ['play|playlist:p1|b', 'play|playlist:p1|c']);
    expect(items.every((i) => i.playable == true), isTrue);
  });

  test('« Reprendre » renvoie le titre en cours', () async {
    final recent = await browser.children(AudioService.recentRootId);
    expect(recent.single.title, 'Titre c');
  });

  test('une liste inconnue est vide', () async {
    expect(await browser.children('playlist:disparue'), isEmpty);
  });

  test('lancer un titre joue sa liste comme file', () async {
    await browser.playFromMediaId('play|playlist:p1|c');
    expect(played.single.$1.id, 'c');
    expect(played.single.$2.map((t) => t.id), ['b', 'c']);
  });

  test('l\'aleatoire ignore les titres sans fichier', () async {
    await browser.playFromMediaId('shuffle');
    final (first, list) = played.single;
    expect(list, hasLength(3));
    expect(list.any((t) => t.id == 'fantome'), isFalse);
    expect(list.first, first);
  });

  test('un id malforme ne lance rien', () async {
    await browser.playFromMediaId('nimporte quoi');
    expect(played, isEmpty);
  });

  test('la recherche vocale joue les resultats, sans requete aleatoire',
      () async {
    await browser.playFromSearch('a');
    expect(played.single.$1.id, 'a');

    played.clear();
    await browser.playFromSearch('  ');
    expect(played.single.$2, hasLength(3));

    played.clear();
    await browser.playFromSearch('introuvable');
    expect(played, isEmpty);
  });
}
