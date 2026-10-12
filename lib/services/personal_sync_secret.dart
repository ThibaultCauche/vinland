import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'navidrome_service.dart';

/// Marqueur (champ "comment") de la playlist privee qui transporte le
/// secret de synchro perso entre les appareils d'un meme compte -- meme
/// mecanisme que les autres miroirs de MusicService (likes, epingles...).
/// Le secret suit directement ce prefixe.
const personalSyncTagPrefix = 'vinland:personal-sync:';

/// Identifiants de la session de synchro perso, derives du secret du compte.
class PersonalSyncIds {
  /// Pour REJOINDRE (publie aussi aux amis via le mirroir "now playing",
  /// voir AppState._maybeBecomePersonalHost : ecoute a la demande).
  final String sessionId;

  /// Pour PILOTER : connu des seuls appareils du compte, il leur permet de
  /// se reprendre la main entre eux sans qu'un ami qui connait le
  /// sessionId puisse le faire (voir services/jam-relay/lib/relay.dart).
  final String hostSecret;

  const PersonalSyncIds(this.sessionId, this.hostSecret);

  /// Deux HMAC distincts du meme secret : connaitre le sessionId (public
  /// entre amis) n'apprend rien sur le hostSecret.
  factory PersonalSyncIds.fromAccountSecret(String accountSecret) {
    final hmac = Hmac(sha256, utf8.encode(accountSecret));
    String derive(String label) => hmac.convert(utf8.encode(label)).toString();
    return PersonalSyncIds(
      derive('vinland-personal-session').substring(0, 32),
      derive('vinland-personal-host'),
    );
  }
}

/// Retrouve le secret parmi les playlists du serveur (fetchPlaylists) :
/// seulement une playlist PRIVEE de ce compte. S'il y en a plusieurs (deux
/// appareils qui l'ont creee en meme temps), la plus petite par id gagne,
/// pour que tous les appareils convergent vers le meme secret.
@visibleForTesting
String? findPersonalSyncSecret(
    List<Map<String, dynamic>> playlists, String username) {
  final candidates = playlists
      .where((pl) =>
          pl['owner'] == username &&
          pl['public'] != true &&
          (pl['comment'] as String? ?? '').startsWith(personalSyncTagPrefix))
      .toList()
    ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  for (final pl in candidates) {
    final secret =
        (pl['comment'] as String).substring(personalSyncTagPrefix.length);
    if (secret.length >= 32) return secret;
  }
  return null;
}

/// Secret aleatoire propre au compte, qui remplace l'ancien
/// sha256("vinland_personal_" + pseudo) : celui-ci se calculait a partir du
/// seul pseudo, visible de tous via les playlists publiques, et permettait a
/// n'importe qui de rejoindre ou de detourner la synchro perso d'un ami.
///
/// Garde en flutter_secure_storage (pas de reseau a chaque sondage) et
/// partage entre les appareils du compte par une playlist privee : Navidrome
/// ne montre une playlist privee qu'a son proprietaire (et aux comptes
/// admin, qui ont de toute facon acces a tout le serveur).
class PersonalSyncSecretStore {
  static final PersonalSyncSecretStore _instance =
      PersonalSyncSecretStore._internal();
  factory PersonalSyncSecretStore() => _instance;
  PersonalSyncSecretStore._internal();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final NavidromeService _navidrome = NavidromeService();
  final Map<String, String> _cache = {};

  String _key(String username) => 'personal_sync_secret_$username';

  /// Le serveur fait foi (une lecture par lancement de l'app, ensuite
  /// cache memoire) : si deux appareils ont cree chacun leur secret en meme
  /// temps, ils convergent au lancement suivant. Le secret garde en local ne
  /// sert que de repli quand le serveur est injoignable. Null si aucun des
  /// deux n'est disponible : la synchro perso attend le prochain essai.
  Future<String?> secretFor(String username) async {
    final cached = _cache[username];
    if (cached != null) return cached;

    final fromServer = await _resolveFromServer(username);
    if (fromServer != null) {
      try {
        await _storage.write(key: _key(username), value: fromServer);
      } catch (e) {
        debugPrint('PersonalSyncSecretStore write error: $e');
      }
      return _cache[username] = fromServer;
    }
    try {
      final stored = await _storage.read(key: _key(username));
      if (stored != null && stored.isNotEmpty) return stored;
    } catch (e) {
      debugPrint('PersonalSyncSecretStore read error: $e');
    }
    return null;
  }

  Future<String?> _resolveFromServer(String username) async {
    if (!_navidrome.isConnected) return null;
    final existing =
        findPersonalSyncSecret(await _navidrome.fetchPlaylists(), username);
    if (existing != null) return existing;

    final random = Random.secure();
    final created = base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final id = await _navidrome.createServerPlaylist('Vinland: synchro',
        comment: '$personalSyncTagPrefix$created', public: false);
    // Echec de creation = serveur injoignable : pas de secret plutot qu'un
    // secret que personne d'autre ne connaitra.
    if (id == null) return null;
    // Relit la liste : si un autre appareil a cree la sienne en meme temps,
    // tout le monde adopte la meme (voir findPersonalSyncSecret).
    return findPersonalSyncSecret(
            await _navidrome.fetchPlaylists(), username) ??
        created;
  }
}
