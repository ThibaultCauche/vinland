import 'package:flutter/foundation.dart';

import '../../models/track.dart';
import 'atomic_json_file.dart';

/// Version du format de `library_<compte>.json`. Sans champ `schemaVersion`
/// = 1 : l'ancien fichier unique (<= 1.3) qui melangeait la bibliotheque et
/// les donnees de l'utilisateur.
const int libraryCacheSchemaVersion = 2;

/// Version du format de `userdata_<compte>.json` (nouveau en v2).
const int userDataSchemaVersion = 1;

/// Cles du fichier unique d'avant qui ne se reconstruisent pas depuis le
/// serveur : fichiers hors ligne, titres introuvables d'un import, ecoutes
/// recentes, playlists locales, epingles, reglages de partage et ids des
/// playlists miroirs. Elles vivent maintenant dans le fichier de donnees
/// perso, que la synchro de bibliotheque ne reecrit jamais.
const List<String> userDataKeys = [
  'offlineFiles',
  'missingTracks',
  'recentPlays',
  'playlists',
  'pinnedItems',
  'shareLikesWithFriends',
  'likesMirrorServerId',
  'shareRecentPlaysWithFriends',
  'recentPlaysMirrorServerId',
  'shareNowPlayingWithFriends',
  'nowPlayingMirrorServerId',
  'sharingConsentAsked',
  'pinnedMirrorServerId',
];

/// Champs d'un titre propres a l'utilisateur : like (et sa date, qui fait
/// l'ordre des « Titres likes »), super-like, compteur d'ecoutes. Gardes
/// par titre dans `trackStates` du fichier de donnees perso, et retires des
/// titres du fichier de bibliotheque.
const List<String> trackUserKeys = [
  'isLiked',
  'superLiked',
  'dateAdded',
  'playCount',
  'lastPlayed',
];

/// Etat perso d'un titre, ou null s'il n'a rien de particulier (pas like,
/// jamais ecoute) : inutile de l'ecrire.
Map<String, dynamic>? trackUserStateOf(Track t) {
  if (!t.isLiked &&
      !t.superLiked &&
      t.dateAdded == null &&
      t.playCount == 0 &&
      t.lastPlayed == null) {
    return null;
  }
  return {
    'isLiked': t.isLiked,
    'superLiked': t.superLiked,
    'dateAdded': t.dateAdded?.toIso8601String(),
    'playCount': t.playCount,
    'lastPlayed': t.lastPlayed?.toIso8601String(),
  };
}

/// Pose l'etat perso [state] sur [t] ; null remet les valeurs par defaut
/// (le fichier de donnees perso fait foi, pas ce que contenait le titre).
void applyTrackUserState(Track t, Map<String, dynamic>? state) {
  t.isLiked = state?['isLiked'] == true;
  t.superLiked = state?['superLiked'] == true;
  t.dateAdded = _date(state?['dateAdded']);
  t.playCount = (state?['playCount'] as num?)?.toInt() ?? 0;
  t.lastPlayed = _date(state?['lastPlayed']);
}

/// Etat perso au format attendu par reconcileTrack (dates en DateTime).
Map<String, dynamic> trackUserStateForReconcile(Map<String, dynamic> state) => {
      'isLiked': state['isLiked'] == true,
      'superLiked': state['superLiked'] == true,
      'dateAdded': _date(state['dateAdded']),
      'playCount': (state['playCount'] as num?)?.toInt() ?? 0,
      'lastPlayed': _date(state['lastPlayed']),
    };

DateTime? _date(Object? raw) =>
    raw is String ? DateTime.tryParse(raw) : (raw is DateTime ? raw : null);

int _versionOf(Map<String, dynamic> data) =>
    (data['schemaVersion'] as num?)?.toInt() ?? 1;

/// Donnees perso tirees d'un fichier unique d'avant la v2.
Map<String, dynamic> userDataFromLegacy(Map<String, dynamic> legacy) {
  final trackStates = <String, dynamic>{};
  for (final raw in (legacy['navidromeTracks'] as List?) ?? const []) {
    if (raw is! Map) continue;
    final t = Track.fromJson(Map<String, dynamic>.from(raw));
    final state = trackUserStateOf(t);
    if (state != null) trackStates[t.id] = state;
  }
  return {
    'schemaVersion': userDataSchemaVersion,
    for (final key in userDataKeys)
      if (legacy.containsKey(key)) key: legacy[key],
    'trackStates': trackStates,
  };
}

/// Migrations du fichier de bibliotheque : l'entree `n` passe de la
/// version `n + 1` a `n + 2`. Toujours ajouter a la fin, jamais modifier
/// une migration deja publiee.
final List<Map<String, dynamic> Function(Map<String, dynamic>)>
    _libraryMigrations = [
  // 1 -> 2 : les donnees perso partent dans userdata_<compte>.json (voir
  // userDataFromLegacy, appele avant par LibraryCacheStore.load).
  (v1) => {
        for (final e in v1.entries)
          if (!userDataKeys.contains(e.key)) e.key: e.value,
        'navidromeTracks': [
          for (final t in (v1['navidromeTracks'] as List?) ?? const [])
            if (t is Map) withoutTrackUserFields(Map<String, dynamic>.from(t)),
        ],
      },
];

/// Migrations du fichier de donnees perso, meme principe.
final List<Map<String, dynamic> Function(Map<String, dynamic>)>
    _userDataMigrations = [];

Map<String, dynamic> _upgrade(
  Map<String, dynamic> data,
  List<Map<String, dynamic> Function(Map<String, dynamic>)> migrations,
  int current,
  String label,
) {
  var version = _versionOf(data);
  if (version > current) {
    // Fichier ecrit par une version plus recente de l'app (retour en
    // arriere) : lu tel quel, les champs inconnus sont ignores.
    debugPrint('CACHE: $label en version $version, plus recente que '
        '$current, lu tel quel');
    return data;
  }
  var out = data;
  while (version < current) {
    out = migrations[version - 1](out);
    version++;
  }
  return {...out, 'schemaVersion': current};
}

/// Fichier de bibliotheque relu, mis a la version courante.
Map<String, dynamic> upgradeLibraryCache(Map<String, dynamic> data) => _upgrade(
    data, _libraryMigrations, libraryCacheSchemaVersion, 'bibliotheque');

/// Fichier de donnees perso relu, mis a la version courante.
Map<String, dynamic> upgradeUserData(Map<String, dynamic> data) =>
    _upgrade(data, _userDataMigrations, userDataSchemaVersion, 'donnees perso');

/// JSON d'un titre pour le fichier de bibliotheque, sans les champs perso.
Map<String, dynamic> withoutTrackUserFields(Map<String, dynamic> track) => {
      for (final e in track.entries)
        if (!trackUserKeys.contains(e.key)) e.key: e.value,
    };

/// Ce que [LibraryCacheStore.load] a trouve sur le disque.
class LoadedCache {
  LoadedCache({
    required this.library,
    required this.userData,
    required this.needsRewrite,
    required this.libraryBytes,
    required this.userDataBytes,
  });

  /// Null si aucune bibliotheque utilisable (premier lancement) : elle se
  /// reconstruit a la prochaine synchro.
  final Map<String, dynamic>? library;

  /// Null si aucune donnee perso trouvee.
  final Map<String, dynamic>? userData;

  /// Vrai si le disque doit etre reecrit tout de suite : migration de
  /// schema, version precedente rechargee, ou vieux cache avec des URL a
  /// jeton (voir SubsonicRefs).
  final bool needsRewrite;

  /// Tailles relues, pour decider s'il faut passer a une base SQLite
  /// (plan de la session 13, etape 4).
  final int libraryBytes;
  final int userDataBytes;
}

/// Les deux fichiers du cache d'un compte :
/// - `library_<compte>.json` : la bibliotheque du serveur (titres, albums),
///   reconstructible a la prochaine synchro ;
/// - `userdata_<compte>.json` : ce qui ne l'est pas (voir [userDataKeys] et
///   [trackUserKeys]), jamais ecrase par une synchro.
class LibraryCacheStore {
  LibraryCacheStore({required String libraryPath, required String userDataPath})
      : _library = AtomicJsonFile(libraryPath),
        _userData = AtomicJsonFile(userDataPath);

  final AtomicJsonFile _library;
  final AtomicJsonFile _userData;

  Future<LoadedCache> load() async {
    final userRead = await _userData.read();
    final libRead = await _library.read();

    var needsRewrite =
        (userRead?.fromBackup ?? false) || (libRead?.fromBackup ?? false);

    Map<String, dynamic>? library;
    Map<String, dynamic>? userData;
    if (libRead != null) {
      final legacy = !libRead.data.containsKey('schemaVersion');
      if (legacy && userRead == null) {
        // Premier lancement apres la mise a jour : on tire les donnees perso
        // du fichier unique avant de le migrer.
        debugPrint('CACHE: migration du fichier unique vers '
            'bibliotheque + donnees perso');
        userData = userDataFromLegacy(libRead.data);
      }
      library = upgradeLibraryCache(libRead.data);
      if (_versionOf(libRead.data) < libraryCacheSchemaVersion) {
        needsRewrite = true;
      }
      if (libRead.raw.contains('/rest/stream') ||
          libRead.raw.contains('/rest/getCoverArt')) {
        needsRewrite = true;
      }
    }
    if (userRead != null) {
      userData = upgradeUserData(userRead.data);
      if (_versionOf(userRead.data) < userDataSchemaVersion) {
        needsRewrite = true;
      }
    } else if (userData != null) {
      needsRewrite = true;
    } else if (library != null) {
      debugPrint('CACHE: donnees perso introuvables (fichier et version '
          'precedente absents ou illisibles), likes et hors-ligne repartent '
          'du serveur');
    }

    return LoadedCache(
      library: library,
      userData: userData,
      needsRewrite: needsRewrite,
      libraryBytes: libRead?.raw.length ?? 0,
      userDataBytes: userRead?.raw.length ?? 0,
    );
  }

  /// Ecrit les donnees perso, puis la bibliotheque si [library] n'est pas
  /// null (null pendant une synchro : la bibliotheque en memoire est
  /// partielle et ne doit pas remplacer la derniere complete). Les donnees
  /// perso d'abord : c'est le fichier qu'on ne peut pas se permettre de
  /// perdre si l'app est tuee entre les deux.
  Future<void> save({
    required Map<String, dynamic> userData,
    Map<String, dynamic>? library,
  }) async {
    await _userData
        .write({...userData, 'schemaVersion': userDataSchemaVersion});
    if (library != null) {
      await _library
          .write({...library, 'schemaVersion': libraryCacheSchemaVersion});
    }
  }
}
