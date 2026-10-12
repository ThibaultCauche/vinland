import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'release_signature.dart';
import 'update_check_service.dart';

/// Auto-update Android : telecharge l'APK de la nouvelle release dans le
/// cache de l'app puis ouvre l'installeur systeme dessus (open_file gere le
/// FileProvider requis depuis Android 7+ pour partager un fichier prive de
/// l'app). Contrairement a Windows, Android impose que l'utilisateur
/// confirme lui-meme l'installation via un ecran systeme -- aucune app
/// tierce ne peut s'auto-installer silencieusement -- mais ca evite le
/// detour par le navigateur pour retelecharger l'APK a la main.
///
/// L'APK n'est ouvert qu'apres verification de son empreinte dans le
/// SHA256SUMS signe de la release : la signature Android protege deja contre
/// un APK signe par une autre cle, mais pas contre l'installation d'une
/// ancienne version vulnerable ou d'un fichier tronque.
class AndroidUpdaterService {
  /// Retourne null si l'installeur a ete ouvert, sinon le message d'erreur
  /// a afficher.
  Future<String?> downloadAndInstall(UpdateInfo update) async {
    if (!Platform.isAndroid) return 'Mise à jour non disponible ici.';
    final url = update.androidDownloadUrl;
    if (url == null) return 'Aucun APK dans cette release.';

    try {
      final verified = await downloadVerifiedAsset(
        assetUrl: url,
        checksumsUrl: update.checksumsUrl,
        signatureUrl: update.signatureUrl,
      );

      final dir = await getTemporaryDirectory();
      final apkPath = p.join(dir.path, 'vinland-update.apk');
      await File(apkPath).writeAsBytes(verified.bytes);

      final result = await OpenFile.open(apkPath);
      return result.type == ResultType.done
          ? null
          : "Impossible d'ouvrir l'installeur Android.";
    } on ReleaseVerificationException catch (e) {
      return e.message;
    } catch (e) {
      return 'Échec du téléchargement de la mise à jour, réessaie plus tard.';
    }
  }
}
