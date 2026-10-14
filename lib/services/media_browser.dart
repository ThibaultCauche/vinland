import 'package:audio_service/audio_service.dart';

import '../models/track.dart';

/// Une liste parcourable dans la voiture : son id, son nom, ses titres.
typedef BrowsableList = ({String id, String title, List<Track> tracks});

/// Ce qu'Android Auto (et tout lecteur qui parcourt la bibliotheque par
/// MediaBrowserService) peut voir et lancer. Branche par AppState sur
/// VinlandAudioHandler une fois la bibliotheque chargee.
///
/// Arborescence : la racine propose les titres likes, les ecoutes de la
/// semaine, un aleatoire sur toute la bibliotheque, les playlists et les
/// nouveautes du NAS ; chaque liste donne ses titres. Un titre se lance
/// dans sa liste (la suite enchaine comme dans l'app).
class VinlandMediaBrowser {
  VinlandMediaBrowser({
    required this.likedTracks,
    required this.weeklyTracks,
    required this.allTracks,
    required this.playlists,
    required this.newAlbums,
    required this.currentTrack,
    required this.play,
    required this.search,
  });

  final List<Track> Function() likedTracks;
  final List<Track> Function() weeklyTracks;
  final List<Track> Function() allTracks;
  final List<BrowsableList> Function() playlists;
  final List<BrowsableList> Function() newAlbums;
  final Track? Function() currentTrack;

  /// Joue [track] avec [list] comme file.
  final Future<void> Function(Track track, List<Track> list) play;
  final List<Track> Function(String query) search;

  static const liked = 'liked';
  static const weekly = 'weekly';
  static const shuffleAll = 'shuffle';
  static const playlistsFolder = 'playlists';
  static const albumsFolder = 'albums';

  /// Au plus ce nombre de titres par liste : la voiture n'en affiche pas
  /// plus utilement, et la liste part en une seule reponse.
  static const maxItems = 300;

  // Indications d'affichage d'Android Auto : liste ou grille.
  static const _listHint = 1;
  static const _gridHint = 2;
  static const _styleExtras = {
    'android.media.browse.CONTENT_STYLE_SUPPORTED': true,
    'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT': _gridHint,
    'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT': _listHint,
  };

  /// Id d'un titre lancable : la liste d'ou il vient, puis le titre.
  static String playableId(String listId, String trackId) =>
      'play|$listId|$trackId';

  Future<List<MediaItem>> children(String parentId) async {
    switch (parentId) {
      case AudioService.browsableRootId:
        return [
          _folder(liked, 'Titres likés'),
          _folder(weekly, 'Écoutés cette semaine'),
          const MediaItem(
            id: shuffleAll,
            title: 'Lecture aléatoire',
            playable: true,
          ),
          _folder(playlistsFolder, 'Playlists'),
          _folder(albumsFolder, 'Nouveautés du NAS'),
        ];
      case AudioService.recentRootId:
        // « Reprendre » sur l'ecran d'accueil d'Android Auto.
        final current = currentTrack();
        return current == null ? const [] : [_trackItem(liked, current)];
      case playlistsFolder:
        return [
          for (final p in playlists()) _folder('playlist:${p.id}', p.title)
        ];
      case albumsFolder:
        return [for (final a in newAlbums()) _folder('album:${a.id}', a.title)];
    }
    final tracks = _listTracks(parentId);
    if (tracks == null) return const [];
    return [
      for (final t in tracks.take(maxItems)) _trackItem(parentId, t),
    ];
  }

  /// Titres de la liste [listId], null si elle n'existe pas (ou plus).
  List<Track>? _listTracks(String listId) {
    if (listId == liked) return likedTracks();
    if (listId == weekly) return weeklyTracks();
    if (listId.startsWith('playlist:')) {
      return _find(playlists(), listId.substring('playlist:'.length));
    }
    if (listId.startsWith('album:')) {
      return _find(newAlbums(), listId.substring('album:'.length));
    }
    return null;
  }

  static List<Track>? _find(List<BrowsableList> lists, String id) {
    for (final l in lists) {
      if (l.id == id) return l.tracks;
    }
    return null;
  }

  Future<void> playFromMediaId(String mediaId) async {
    if (mediaId == shuffleAll) {
      final pool = allTracks().where((t) => !t.isPlaceholder).toList();
      if (pool.isEmpty) return;
      final shuffled = List.of(pool)..shuffle();
      await play(shuffled.first, shuffled);
      return;
    }
    final parts = mediaId.split('|');
    if (parts.length < 3 || parts.first != 'play') return;
    final trackId = parts.last;
    final listId = parts.sublist(1, parts.length - 1).join('|');
    final list = _listTracks(listId) ?? const <Track>[];
    final track = list.where((t) => t.id == trackId).firstOrNull ??
        allTracks().where((t) => t.id == trackId).firstOrNull;
    if (track == null) return;
    await play(track, list.isEmpty ? [track] : list);
  }

  /// « Ok Google, mets Daft Punk sur Vinland » : les titres trouves, le
  /// premier en tete. Sans requete (« mets de la musique »), aleatoire.
  Future<void> playFromSearch(String query) async {
    if (query.trim().isEmpty) return playFromMediaId(shuffleAll);
    final found = search(query);
    if (found.isEmpty) return;
    await play(found.first, found);
  }

  Future<List<MediaItem>> searchItems(String query) async => [
        for (final t in search(query).take(50)) _trackItem('search', t),
      ];

  MediaItem _folder(String id, String title) => MediaItem(
        id: id,
        title: title,
        playable: false,
        extras: _styleExtras,
      );

  MediaItem _trackItem(String listId, Track t) {
    final cover = t.coverPath;
    return MediaItem(
      id: playableId(listId, t.id),
      title: t.title,
      artist: t.artist,
      album: t.album,
      duration: t.duration,
      playable: true,
      artUri: cover == null
          ? null
          : cover.startsWith('http')
              ? Uri.parse(cover)
              : Uri.file(cover),
    );
  }
}
