import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

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

  const UpdateInfo({
    required this.latestVersion,
    required this.releaseUrl,
    this.windowsDownloadUrl,
    this.androidDownloadUrl,
  });
}

/// Verifie s'il existe une release GitHub plus recente que la version
/// installee. Pas de mise a jour silencieuse (remplacer un exe non signe
/// tout seul serait justement le genre de comportement suspect que Windows/
/// antivirus detestent) : juste un signal pour inviter au telechargement
/// manuel de la nouvelle version.
class UpdateCheckService {
  static const _apiUrl =
      'https://api.github.com/repos/Tibobg/vinland/releases/latest';

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http
          .get(Uri.parse(_apiUrl), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String?)?.trim();
      final url = data['html_url'] as String?;
      if (tag == null || url == null) return null;

      final latest = _parseVersion(tag);
      final info = await PackageInfo.fromPlatform();
      final current = _parseVersion(info.version);
      if (latest == null || current == null) return null;

      if (_isNewer(latest, current)) {
        final assets = (data['assets'] as List?) ?? [];
        String? windowsUrl;
        String? androidUrl;
        for (final asset in assets) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (name.contains('windows') && name.endsWith('.zip')) {
            windowsUrl = asset['browser_download_url'] as String?;
          } else if (name.contains('android') && name.endsWith('.apk')) {
            androidUrl = asset['browser_download_url'] as String?;
          }
        }
        return UpdateInfo(
          latestVersion: tag,
          releaseUrl: url,
          windowsDownloadUrl: windowsUrl,
          androidDownloadUrl: androidUrl,
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// "v1.2.3" ou "1.2.3" -> [1, 2, 3]. Ignore tout suffixe (ex: "-beta").
  List<int>? _parseVersion(String raw) {
    final cleaned = raw.startsWith('v') ? raw.substring(1) : raw;
    final numeric = cleaned.split('+').first.split('-').first;
    final parts = numeric.split('.');
    try {
      return parts.map(int.parse).toList();
    } catch (_) {
      return null;
    }
  }

  bool _isNewer(List<int> latest, List<int> current) {
    final length = latest.length > current.length ? latest.length : current.length;
    for (var i = 0; i < length; i++) {
      final l = i < latest.length ? latest[i] : 0;
      final c = i < current.length ? current[i] : 0;
      if (l != c) return l > c;
    }
    return false;
  }
}
