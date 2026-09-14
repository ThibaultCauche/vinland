import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/models/playlist.dart';
import 'package:vinland/services/music_service.dart';

Map<String, dynamic> _serverPlaylist({
  required String id,
  String name = 'Ma playlist',
  bool public = false,
  String comment = '',
}) =>
    {'id': id, 'name': name, 'owner': 'me', 'public': public, 'comment': comment};

void main() {
  group('planPlaylistSync', () {
    test(
        'decouvre une playlist qui existe sur le serveur sous ce compte mais jamais creee sur cet appareil',
        () {
      // Regression du 14/09 signalee par l'utilisateur : une playlist creee
      // pour un ami depuis un autre appareil restait invisible pour
      // toujours chez lui une fois connecte sur le sien.
      final plan = planPlaylistSync(
        [_serverPlaylist(id: 'srv-1', name: 'Playlist de vacances')],
        [], // rien connu localement sur cet appareil
        ignoredServerIds: {},
        collabTagPrefix: 'vinland:collab:',
      );

      expect(plan.toRefresh, isEmpty);
      expect(plan.discovered, hasLength(1));
      expect(plan.discovered.single.name, 'Playlist de vacances');
      expect(plan.discovered.single.serverId, 'srv-1');
    });

    test('rafraichit une playlist deja connue localement au lieu de la redecouvrir',
        () {
      final local = Playlist(id: 'local-1', name: 'Ancien nom', serverId: 'srv-1');
      final plan = planPlaylistSync(
        [_serverPlaylist(id: 'srv-1', name: 'Nouveau nom', public: true)],
        [local],
        ignoredServerIds: {},
        collabTagPrefix: 'vinland:collab:',
      );

      expect(plan.discovered, isEmpty);
      expect(plan.toRefresh, [local]);
      // Le nom local n'est pas ecrase par planPlaylistSync (juste isPublic) :
      // seul l'appelant (fetchPlaylistSongIds) touche au contenu ; le nom
      // reste celui deja affiche localement.
      expect(local.isPublic, isTrue);
    });

    test('ignore les playlists miroir (likes/ecoutes recentes/now playing)', () {
      final plan = planPlaylistSync(
        [_serverPlaylist(id: 'mirror-1')],
        [],
        ignoredServerIds: {'mirror-1'},
        collabTagPrefix: 'vinland:collab:',
      );

      expect(plan.toRefresh, isEmpty);
      expect(plan.discovered, isEmpty);
    });

    test('ignore les sous-listes de playlist collaborative (mergees ailleurs)', () {
      final plan = planPlaylistSync(
        [_serverPlaylist(id: 'collab-1', comment: 'vinland:collab:abc123')],
        [],
        ignoredServerIds: {},
        collabTagPrefix: 'vinland:collab:',
      );

      expect(plan.toRefresh, isEmpty);
      expect(plan.discovered, isEmpty);
    });
  });
}
