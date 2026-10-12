import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/services/legacy_file_migration.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('vinland_migration'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('le cache de Documents est deplace vers le dossier support', () async {
    final legacy = File('${tmp.path}/Documents/cache/library_x.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('ancien');
    final target = File('${tmp.path}/Support/cache/library_x.json');

    await migrateLegacyFile(legacy: legacy, target: target);

    expect(target.readAsStringSync(), 'ancien');
    expect(legacy.existsSync(), isFalse);
  });

  test('un cache deja present au nouvel endroit n est pas ecrase', () async {
    final legacy = File('${tmp.path}/Documents/cache/library_x.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('ancien');
    final target = File('${tmp.path}/Support/cache/library_x.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('recent');

    await migrateLegacyFile(legacy: legacy, target: target);

    expect(target.readAsStringSync(), 'recent');
    // L'ancien (avec URL a jeton) disparait quand meme de Documents.
    expect(legacy.existsSync(), isFalse);
  });

  test('sans ancien cache, rien ne se passe', () async {
    final target = File('${tmp.path}/Support/cache/library_x.json');
    await migrateLegacyFile(
        legacy: File('${tmp.path}/absent.json'), target: target);
    expect(target.existsSync(), isFalse);
  });
}
