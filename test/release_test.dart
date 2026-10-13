import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garde-fous de release : ce que le tag `vX.Y.Z` publie doit correspondre
/// au code, sinon la mise a jour automatique ou les notes de version
/// mentent aux amis (voir « Publier une nouvelle version » dans CLAUDE.md).
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final changelog = File('CHANGELOG.md').readAsStringSync();
  final version = RegExp(r'^version: (\d+\.\d+\.\d+)\+(\d+)$', multiLine: true)
      .firstMatch(pubspec);

  test('la version de pubspec.yaml suit X.Y.Z+build', () {
    expect(version, isNotNull);
  });

  test(
      'la version de pubspec.yaml est la derniere du journal des '
      'modifications (sinon la release publie un journal en retard)', () {
    final firstRelease =
        RegExp(r'^## \[(\d+\.\d+\.\d+)\] - \d{4}-\d{2}-\d{2}$', multiLine: true)
            .firstMatch(changelog);
    expect(firstRelease?.group(1), version!.group(1));
    expect(changelog, contains('[${version.group(1)}]: https://'),
        reason: 'lien de comparaison en bas du journal');
  });

  test('une version majeure ou mineure a ses notes pour les amis', () {
    final v = version!.group(1)!;
    if (v.endsWith('.0')) {
      expect(File('docs/release-notes/v$v.md').existsSync(), isTrue,
          reason: 'docs/release-notes/v$v.md manquant');
    }
  });

  test(
      "l'identifiant Android ne change pas (sinon la mise a jour ne "
      "s'installe plus chez les amis, voir ADR 0007)", () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('applicationId = "com.example.vinland"'));
  });
}
