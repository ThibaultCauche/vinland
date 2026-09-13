import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Auto-update Android : telecharge l'APK de la nouvelle release dans le
/// cache de l'app puis ouvre l'installeur systeme dessus (open_file gere le
/// FileProvider requis depuis Android 7+ pour partager un fichier prive de
/// l'app). Contrairement a Windows, Android impose que l'utilisateur
/// confirme lui-meme l'installation via un ecran systeme -- aucune app
/// tierce ne peut s'auto-installer silencieusement -- mais ca evite le
/// detour par le navigateur pour retelecharger l'APK a la main.
class AndroidUpdaterService {
  Future<bool> downloadAndInstall(String downloadUrl) async {
    if (!Platform.isAndroid) return false;

    try {
      final response = await http
          .get(Uri.parse(downloadUrl))
          .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return false;
      }

      final dir = await getTemporaryDirectory();
      final apkPath = p.join(dir.path, 'vinland-update.apk');
      await File(apkPath).writeAsBytes(response.bodyBytes);

      final result = await OpenFile.open(apkPath);
      return result.type == ResultType.done;
    } catch (e) {
      return false;
    }
  }
}
