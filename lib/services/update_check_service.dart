import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'release_signature.dart';

class UpdateInfo {
  final String latestVersion;
  final String releaseUrl;

  /// URL de telechargement direct de l'asset Windows (zip) attache a la
  /// release, si trouve (nom contenant "windows"). Null si la release n'a
  /// pas d'asset Windows -- dans ce cas on retombe sur l'ouverture de
  /// releaseUrl dans le navigateur.
  final String? windowsDownloadUrl;

  /// Meme principe pour l'APK Android (nom contenant "android", terminant
  /// par ".apk") : permet a AndroidUpdaterService de le telecharger et de
  /// lancer l'installeur systeme directement, sans passer par le navigateur.
  final String? androidDownloadUrl;

  /// SHA256SUMS et sa signature minisign (voir release_signature.dart). Null
  /// pour les releases publiees avant la verification : l'auto-update les
  /// refuse alors avec un message clair.
  final String? checksumsUrl;
  final String? signatureUrl;

  const UpdateInfo({
    required this.latestVersion,
    required this.releaseUrl,
    this.windowsDownloadUrl,
    this.androidDownloadUrl,
    this.checksumsUrl,
    this.signatureUrl,
  });
}

/// Resultat d'une verification : [info] est la mise a jour disponible (ou
/// null), [rateLimited] indique que GitHub a refuse la requete (limite de
/// 60 requetes/heure par adresse IP) et que [info] vient du dernier resultat
/// connu.
typedef UpdateCheckResult = ({UpdateInfo? info, bool rateLimited});

/// Verifie s'il existe une release GitHub plus recente que la version
/// installee.
///
/// L'API GitHub sans compte est limitee a 60 requetes par heure et par IP :
/// en soiree, tous les telephones derriere la meme box partagent ce quota,
/// et chaque retour au premier plan declenchait une verification. On espace
/// donc les verifications automatiques (une par heure et par appareil au
/// plus), on garde le dernier resultat en memoire persistante, et sur un 403
/// ou 429 on attend la fin de la fenetre indiquee par GitHub.
class UpdateCheckService {
  static const _apiUrl =
      'https://api.github.com/repos/ThibaultCauche/vinland/releases/latest';

  static const minInterval = Duration(hours: 1);

  static const _keyLastCheck = 'update_check_last_at';
  static const _keyBlockedUntil = 'update_check_blocked_until';
  static const _keyCachedRelease = 'update_check_cached_release';

  final http.Client? _client;
  final DateTime Function() _now;
  final Future<String> Function() _currentVersion;

  UpdateCheckService({
    http.Client? client,
    DateTime Function()? now,
    Future<String> Function()? currentVersion,
  })  : _client = client,
        _now = now ?? DateTime.now,
        _currentVersion = currentVersion ??
            (() async => (await PackageInfo.fromPlatform()).version);

  /// [force] : verification demandee par l'utilisateur (bouton des
  /// Parametres), qui passe outre l'intervalle d'une heure mais pas un
  /// blocage explicite de GitHub (inutile, la requete serait refusee).
  Future<UpdateCheckResult> checkForUpdate({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nowMs = _now().millisecondsSinceEpoch;
      final current = parseVersion(await _currentVersion());

      UpdateInfo? fromCache() {
        final raw = prefs.getString(_keyCachedRelease);
        if (raw == null || current == null) return null;
        try {
          return updateInfoFromRelease(
              jsonDecode(raw) as Map<String, dynamic>, current);
        } catch (_) {
          return null;
        }
      }

      final blockedUntil = prefs.getInt(_keyBlockedUntil) ?? 0;
      if (nowMs < blockedUntil) {
        return (info: fromCache(), rateLimited: true);
      }
      final lastCheck = prefs.getInt(_keyLastCheck) ?? 0;
      if (!force && nowMs - lastCheck < minInterval.inMilliseconds) {
        return (info: fromCache(), rateLimited: false);
      }

      final client = _client ?? http.Client();
      final http.Response response;
      try {
        response = await client.get(Uri.parse(_apiUrl), headers: {
          'Accept': 'application/vnd.github+json'
        }).timeout(const Duration(seconds: 8));
      } finally {
        if (_client == null) client.close();
      }

      if (response.statusCode == 403 || response.statusCode == 429) {
        await prefs.setInt(
            _keyBlockedUntil, _blockedUntil(response.headers, nowMs));
        return (info: fromCache(), rateLimited: true);
      }
      if (response.statusCode != 200) {
        return (info: fromCache(), rateLimited: false);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await prefs.setInt(_keyLastCheck, nowMs);
      await prefs.setString(_keyCachedRelease, jsonEncode(_slim(data)));
      if (current == null) return (info: null, rateLimited: false);
      return (info: updateInfoFromRelease(data, current), rateLimited: false);
    } catch (e) {
      return (info: null, rateLimited: false);
    }
  }

  /// GitHub donne la fin de la fenetre dans `x-ratelimit-reset` (secondes
  /// epoch) ou un delai dans `retry-after` ; a defaut, on attend une heure.
  static int _blockedUntil(Map<String, String> headers, int nowMs) {
    final retryAfter = int.tryParse(headers['retry-after'] ?? '');
    if (retryAfter != null) return nowMs + retryAfter * 1000;
    final reset = int.tryParse(headers['x-ratelimit-reset'] ?? '');
    if (reset != null && reset * 1000 > nowMs) return reset * 1000;
    return nowMs + minInterval.inMilliseconds;
  }

  /// Ne garde que ce qui sert : la reponse complete de l'API fait plusieurs
  /// Ko (notes de release, auteur...).
  static Map<String, dynamic> _slim(Map<String, dynamic> data) => {
        'tag_name': data['tag_name'],
        'html_url': data['html_url'],
        'assets': [
          for (final a in (data['assets'] as List? ?? []))
            {
              'name': a['name'],
              'browser_download_url': a['browser_download_url'],
            }
        ],
      };

  /// Construit l'UpdateInfo d'une release de l'API GitHub, ou null si elle
  /// n'est pas plus recente que [current].
  @visibleForTesting
  static UpdateInfo? updateInfoFromRelease(
      Map<String, dynamic> data, List<int> current) {
    final tag = (data['tag_name'] as String?)?.trim();
    final url = data['html_url'] as String?;
    if (tag == null || url == null) return null;
    final latest = parseVersion(tag);
    if (latest == null || !isNewer(latest, current)) return null;

    final assets = (data['assets'] as List?) ?? [];
    String? windowsUrl;
    String? androidUrl;
    String? checksumsUrl;
    String? signatureUrl;
    for (final asset in assets) {
      final rawName = asset['name'] as String? ?? '';
      final name = rawName.toLowerCase();
      final downloadUrl = asset['browser_download_url'] as String?;
      if (rawName == kChecksumsAssetName) {
        checksumsUrl = downloadUrl;
      } else if (rawName == kChecksumsSignatureAssetName) {
        signatureUrl = downloadUrl;
      } else if (name.contains('windows') && name.endsWith('.zip')) {
        windowsUrl = downloadUrl;
      } else if (name.contains('android') && name.endsWith('.apk')) {
        androidUrl = downloadUrl;
      }
    }
    return UpdateInfo(
      latestVersion: tag,
      releaseUrl: url,
      windowsDownloadUrl: windowsUrl,
      androidDownloadUrl: androidUrl,
      checksumsUrl: checksumsUrl,
      signatureUrl: signatureUrl,
    );
  }

  /// "v1.2.3" ou "1.2.3" -> [1, 2, 3]. Ignore tout suffixe (ex: "-beta").
  @visibleForTesting
  static List<int>? parseVersion(String raw) {
    final cleaned = raw.startsWith('v') ? raw.substring(1) : raw;
    final numeric = cleaned.split('+').first.split('-').first;
    final parts = numeric.split('.');
    try {
      return parts.map(int.parse).toList();
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static bool isNewer(List<int> latest, List<int> current) {
    final length =
        latest.length > current.length ? latest.length : current.length;
    for (var i = 0; i < length; i++) {
      final l = i < latest.length ? latest[i] : 0;
      final c = i < current.length ? current[i] : 0;
      if (l != c) return l > c;
    }
    return false;
  }
}
