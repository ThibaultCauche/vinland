import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/app_state.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../widgets/user_avatar.dart';

const String _scheme = 'vinland';

/// Cle de navigation globale : permet d'afficher un SnackBar d'erreur quand
/// un lien vinland:// est ouvert en dehors de tout BuildContext local (ex:
/// lien reçu pendant que l'app est en arriere-plan).
final GlobalKey<NavigatorState> vinlandNavigatorKey = GlobalKey<NavigatorState>();

String trackShareLink(Track track) => '$_scheme://track/${track.id}';
String albumShareLink(Album album) => '$_scheme://album/${album.id}';

/// Id a utiliser pour partager une playlist : celui du SERVEUR Navidrome
/// (playlist.serverId), jamais l'id LOCAL (playlist.id, ex: horodatage de
/// creation) qui n'a aucun sens pour un autre utilisateur -- cote
/// destinataire, les playlists des amis ne sont connues que par leur id
/// serveur (voir MusicService.fetchFriends), deux valeurs differentes des
/// qu'une playlist a ete synchronisee. Un lien construit avec l'id local ne
/// se resout donc jamais que pour son propre proprietaire (retour
/// utilisateur : partage recu mais impossible a ouvrir, ni en lien externe
/// ni en boite de reception). Retourne null si la playlist n'est pas
/// encore synchronisee (pas d'id serveur) : rien d'utilisable a partager
/// dans ce cas, a l'appelant de le signaler plutot que d'envoyer un lien
/// casse.
String? playlistShareId(Playlist playlist) => playlist.serverId;
String? playlistShareLink(Playlist playlist) {
  final id = playlistShareId(playlist);
  return id == null ? null : '$_scheme://playlist/$id';
}

Future<void> _shareText(String text) =>
    SharePlus.instance.share(ShareParams(text: text));

Future<void> shareTrack(Track track) => _shareText(
      'Ecoute "${track.title}" de ${track.artist} sur Vinland\n'
      '${trackShareLink(track)}',
    );

Future<void> shareAlbum(Album album) => _shareText(
      'Ecoute l\'album "${album.title}" de ${album.artist} sur Vinland\n'
      '${albumShareLink(album)}',
    );

enum _PlaylistShareChoice { shareAnyway, makePublic }

/// Si la playlist est privee, ni le lien ni un partage en boite de reception
/// ne s'ouvriront jamais chez le destinataire (Navidrome ne renvoie les
/// playlists d'un autre utilisateur que si elles sont publiques -- voir
/// MusicService.fetchFriends). On ne la rend donc jamais publique sans
/// demander : on previent et on laisse le choix. Retourne false si
/// l'utilisateur annule (rien a partager dans ce cas).
Future<bool> _ensurePlaylistShareable(
    BuildContext context, Playlist playlist) async {
  if (playlist.isPublic) return true;
  final choice = await showDialog<_PlaylistShareChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title:
          const Text('Playlist privee', style: TextStyle(color: Colors.white)),
      content: const Text(
        "Cette playlist est privee : tant qu'elle le reste, le destinataire "
        "ne pourra pas y acceder.",
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, _PlaylistShareChoice.shareAnyway),
          child: const Text('Partager quand meme'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, _PlaylistShareChoice.makePublic),
          child: const Text('Rendre publique et partager'),
        ),
      ],
    ),
  );
  if (choice == null) return false;
  if (choice == _PlaylistShareChoice.makePublic) {
    if (!context.mounted) return false;
    await context.read<AppState>().setPlaylistPublic(playlist.id, true);
  }
  return true;
}

void _showNotYetSyncedError(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
          "Cette playlist n'est pas encore synchronisee avec le serveur, "
          "reessaie dans quelques instants."),
      backgroundColor: Color(0xFF2A2A2A),
    ),
  );
}

Future<void> sharePlaylist(BuildContext context, Playlist playlist) async {
  final proceed = await _ensurePlaylistShareable(context, playlist);
  if (!proceed) return;
  if (!context.mounted) return;
  final link = playlistShareLink(playlist);
  if (link == null) return _showNotYetSyncedError(context);
  await _shareText('Ecoute la playlist "${playlist.name}" sur Vinland\n$link');
}

/// "Envoyer a un ami" (phase 2 du partage, contrairement au partage externe
/// ci-dessus qui compte sur un outil tiers -- SMS/WhatsApp -- pour faire
/// passer le lien) : choisit un ami dans la liste, puis pose le partage dans
/// sa boite de reception (voir AppState.sendShareToFriend/ShareInboxService).
/// N'est jamais affiche tant que le service n'est pas configure (voir
/// AppState.shareInboxConfigured) -- a l'appelant de ne montrer l'entree de
/// menu que dans ce cas.
Future<void> showSendToFriendDialog(
  BuildContext context, {
  required String type,
  // Requis sauf pour type == 'playlist' (voir playlistForPrivacyCheck, qui
  // fournit l'id serveur correct a sa place -- jamais playlist.id, l'id
  // LOCAL, qui ne voudrait rien dire pour le destinataire).
  String? itemId,
  required String title,
  required String subtitle,
  // Uniquement pour type == 'playlist' : verifie/demande avant d'envoyer
  // une playlist privee (voir _ensurePlaylistShareable), et fournit le bon
  // id a partager (playlist.serverId, pas playlist.id -- voir
  // playlistShareId).
  Playlist? playlistForPrivacyCheck,
}) async {
  assert(itemId != null || playlistForPrivacyCheck != null);
  var resolvedItemId = itemId;
  if (playlistForPrivacyCheck != null) {
    final proceed =
        await _ensurePlaylistShareable(context, playlistForPrivacyCheck);
    if (!proceed) return;
    final serverId = playlistShareId(playlistForPrivacyCheck);
    if (serverId == null) {
      if (!context.mounted) return;
      return _showNotYetSyncedError(context);
    }
    resolvedItemId = serverId;
  }
  if (!context.mounted) return;
  final state = context.read<AppState>();
  if (state.friends.isEmpty && !state.loadingFriends) {
    await state.loadFriends();
  }
  if (!context.mounted) return;
  if (state.friends.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Aucun ami pour le moment.'),
        backgroundColor: Color(0xFF2A2A2A),
      ),
    );
    return;
  }

  final friendUsername = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Envoyer a...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(color: Color(0xFF2A2A2A), height: 1),
          ...state.friends.map((f) => ListTile(
                leading: UserAvatar(username: f.username, size: 36),
                title: Text(f.username,
                    style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, f.username),
              )),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (friendUsername == null) return;

  final ok = await state.sendShareToFriend(
    toUsername: friendUsername,
    type: type,
    itemId: resolvedItemId!,
    title: title,
    subtitle: subtitle,
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content:
          Text(ok ? 'Envoye a $friendUsername' : "Echec de l'envoi"),
      backgroundColor: const Color(0xFF2A2A2A),
    ),
  );
}

/// Recoit les liens vinland://track|album|playlist/<id> (ouverts depuis une
/// autre app -- SMS, WhatsApp... -- via le partage natif ci-dessus) et
/// rouvre l'app sur l'element concerne. Cote reception uniquement : pas de
/// messagerie/partage cible dans l'app pour l'instant (fera l'objet d'un
/// chantier separe).
class DeepLinkService {
  DeepLinkService(this._state);
  final AppState _state;
  final _appLinks = AppLinks();

  Future<void> init() async {
    if (!kIsWeb && Platform.isWindows) {
      unawaited(_registerWindowsProtocol());
    }
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) unawaited(_handle(initial));
    } catch (e) {
      debugPrint('Deep link: lien initial illisible: $e');
    }
    _appLinks.uriLinkStream.listen(_handle, onError: (e) {
      debugPrint('Deep link: erreur stream: $e');
    });
  }

  /// Sur Windows le protocole n'est pas installe par un installeur (l'app
  /// est distribuee en zip) : on l'enregistre nous-memes dans le registre de
  /// l'utilisateur courant (pas besoin de droits admin) a chaque demarrage.
  /// Idempotent et bon marche, s'auto-corrige si l'auto-update deplace
  /// l'exe.
  Future<void> _registerWindowsProtocol() async {
    final exe = Platform.resolvedExecutable;
    try {
      await Process.run('reg', [
        'add',
        'HKCU\\Software\\Classes\\$_scheme',
        '/ve',
        '/d',
        'URL:Vinland',
        '/f',
      ]);
      await Process.run('reg', [
        'add',
        'HKCU\\Software\\Classes\\$_scheme',
        '/v',
        'URL Protocol',
        '/d',
        '',
        '/f',
      ]);
      await Process.run('reg', [
        'add',
        'HKCU\\Software\\Classes\\$_scheme\\shell\\open\\command',
        '/ve',
        '/d',
        '"$exe" "%1"',
        '/f',
      ]);
    } catch (e) {
      debugPrint('Deep link: echec enregistrement protocole Windows: $e');
    }
  }

  Future<void> _handle(Uri uri) async {
    if (uri.scheme != _scheme) return;
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) return;

    // La bibliotheque se remplit progressivement apres le login (sync
    // Navidrome en arriere-plan) : on attend qu'elle soit prete plutot que
    // d'echouer si le lien est ouvert juste au demarrage de l'app.
    await _waitUntilReady();

    // Resolution + navigation partagees avec la boite de reception (un
    // partage recu s'ouvre exactement de la meme facon, voir
    // AppState.openSharedItem).
    final ok = await _state.openSharedItem(type: uri.host, id: id);
    if (!ok) _notFound();
  }

  /// isLoggedIn ne reflete que des identifiants presents en local (pas de
  /// reseau) : sur un demarrage a froid via lien (app tuee puis relancee
  /// par le tap), il redevenait vrai bien avant que l'authentification
  /// live aupres du serveur (jusqu'a ~10s, NAS lent/injoignable) ou le
  /// premier fetchFriends() n'aient eu le temps d'aboutir -- resolution
  /// tentee trop tot, toujours en echec meme pour un element qui existe
  /// reellement (retour utilisateur : lien "introuvable" a chaque fois).
  /// Attend donc aussi isNavidromeConnected, pas juste isLoggedIn.
  Future<void> _waitUntilReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!_state.isLoggedIn ||
        _state.isInitializing ||
        !_state.isNavidromeConnected) {
      if (DateTime.now().isAfter(deadline)) return;
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  void _notFound() {
    final ctx = vinlandNavigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        content: Text(
            "Lien invalide, ou l'element est prive/introuvable sur ce serveur."),
        backgroundColor: Color(0xFF2A2A2A),
      ),
    );
  }
}
