import 'dart:io';

/// Deplace [legacy] vers [target] une seule fois : copie si [target]
/// n'existe pas encore, puis supprime [legacy] dans tous les cas (un cache
/// plus recent au nouvel endroit gagne toujours). Copie + suppression
/// plutot que rename : les deux dossiers peuvent etre sur des volumes
/// differents (Documents redirige vers OneDrive sous Windows).
Future<void> migrateLegacyFile({
  required File legacy,
  required File target,
}) async {
  if (!await legacy.exists()) return;
  if (!await target.exists()) {
    await target.parent.create(recursive: true);
    await legacy.copy(target.path);
  }
  await legacy.delete();
}
