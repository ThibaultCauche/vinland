import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vinland/data/cache/atomic_json_file.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vinland_atomic_');
    path = p.join(dir.path, 'library_u1.json');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  List<String> filesIn(Directory d) =>
      d.listSync().map((e) => p.basename(e.path)).toList()..sort();

  test('ce qui est ecrit se relit tel quel', () async {
    await AtomicJsonFile(path).write({'a': 1});
    final read = await AtomicJsonFile(path).read();
    expect(read!.data, {'a': 1});
    expect(read.fromBackup, isFalse);
  });

  test('premier lancement : rien a relire', () async {
    expect(await AtomicJsonFile(path).read(), isNull);
  });

  test(
      'un fichier tronque par un arret brutal est remplace par la version '
      'precedente', () async {
    final file = AtomicJsonFile(path);
    await file.write({'version': 1});
    await file.write({'version': 2});
    // Ce que laissait l'ancienne ecriture en place quand Android tuait l'app.
    File(path).writeAsStringSync('{"version": 3, "navidromeTr');

    final read = await file.read();
    expect(read!.data, {'version': 1});
    expect(read.fromBackup, isTrue);
    // Le fichier abime est garde a cote pour comprendre ce qui s'est passe.
    expect(File('$path.corrupt').readAsStringSync(), contains('"version": 3'));
  });

  test('app tuee entre les deux renommages : la version precedente sert',
      () async {
    final file = AtomicJsonFile(path);
    await file.write({'version': 1});
    await file.write({'version': 2});
    File(path).renameSync('$path.bak');

    final read = await file.read();
    expect(read!.data, {'version': 2});
    expect(read.fromBackup, isTrue);
  });

  test('app tuee pendant l ecriture du temporaire : rien n est perdu',
      () async {
    final file = AtomicJsonFile(path);
    await file.write({'version': 1});
    final orphan = File('$path.999.0.tmp')..writeAsStringSync('{"vers');
    orphan.setLastModifiedSync(
        DateTime.now().subtract(const Duration(minutes: 5)));

    final read = await file.read();
    expect(read!.data, {'version': 1});
    expect(read.fromBackup, isFalse);
    // Le vieux temporaire est nettoye.
    expect(orphan.existsSync(), isFalse);
  });

  test('un temporaire recent (autre isolate en train d ecrire) est garde',
      () async {
    final file = AtomicJsonFile(path);
    await file.write({'version': 1});
    final inFlight = File('$path.999.0.tmp')..writeAsStringSync('{"vers');

    await file.read();
    expect(inFlight.existsSync(), isTrue);
  });

  test('deux sauvegardes rapprochees : la derniere gagne, aucune ne se perd',
      () async {
    final file = AtomicJsonFile(path);
    final data = {'version': 1};
    final first = file.write(data);
    // Modifier la map apres l'appel ne change pas ce qui est ecrit.
    data['version'] = 99;
    final second = AtomicJsonFile(path).write({'version': 2});
    await Future.wait([first, second]);

    expect((await file.read())!.data, {'version': 2});
    expect(File('$path.bak').readAsStringSync(), '{"version":1}');
    expect(filesIn(dir), ['library_u1.json', 'library_u1.json.bak']);
  });

  test('beaucoup de sauvegardes en rafale laissent un fichier complet',
      () async {
    final file = AtomicJsonFile(path);
    await Future.wait([
      for (var i = 0; i < 30; i++)
        file.write({
          'i': i,
          'tracks': List.generate(200, (j) => 'titre $j'),
        }),
    ]);
    final read = await file.read();
    expect(read!.data['i'], 29);
    expect(read.fromBackup, isFalse);
  });

  test('principal et version precedente illisibles : rien plutot qu un crash',
      () async {
    File(path).writeAsStringSync('{"a"');
    File('$path.bak').writeAsStringSync('');
    expect(await AtomicJsonFile(path).read(), isNull);
  });

  test('une ecriture ratee ne bloque pas les suivantes', () async {
    final file = AtomicJsonFile(path);
    // Un dossier a la place du fichier : le renommage echoue.
    Directory(path).createSync();
    await expectLater(
        file.write({'a': 1}), throwsA(isA<FileSystemException>()));
    Directory(path).deleteSync();
    await file.write({'a': 2});
    expect((await file.read())!.data, {'a': 2});
    expect(filesIn(dir).where((f) => f.endsWith('.tmp')), isEmpty);
  });
}
