import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/services/local_import_planner.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vinland_import'));
  tearDown(() => dir.deleteSync(recursive: true));

  File file(String name, int bytes) =>
      File('${dir.path}/$name')..writeAsBytesSync(List.filled(bytes, 0));

  test('lots limites en taille et en nombre de fichiers', () async {
    final files = [for (var i = 0; i < 5; i++) file('f$i.mp3', 40)];
    final bySize = await batchFilesForImport(files, maxBytes: 100);
    expect(bySize.map((b) => b.length), [2, 2, 1]);
    final byCount = await batchFilesForImport(files, maxFiles: 3);
    expect(byCount.map((b) => b.length), [3, 2]);
  });

  test('un fichier plus gros que la limite part seul dans son lot', () async {
    final batches = await batchFilesForImport(
        [file('gros.flac', 300), file('petit.mp3', 10)],
        maxBytes: 100);
    expect(batches.map((b) => b.length), [1, 1]);
    expect(await batchFilesForImport(const []), isEmpty);
  });

  test('fichier deja sur le NAS (tags identiques) : pas re-uploade', () async {
    final library = [
      Track(
          id: 'navidrome_1',
          title: 'Get Lucky',
          artist: 'Daft Punk',
          album: 'RAM',
          duration: Duration.zero),
    ];
    final dejaLa = file('a.mp3', 1);
    final nouveau = file('b.mp3', 1);
    final sansTags = file('c.mp3', 1);
    final (toUpload, present) = await splitAlreadyInLibrary(
      [dejaLa, nouveau, sansTags],
      library,
      readTags: (f) async => switch (f.path.split('/').last) {
        'a.mp3' => ('Daft Punk', 'Get Lucky'),
        'b.mp3' => ('Justice', 'D.A.N.C.E.'),
        _ => null,
      },
    );
    expect(present, ['navidrome_1']);
    expect(toUpload.map((f) => f.path), [nouveau.path, sansTags.path]);
  });

  test('tags illisibles : null plutot qu\'une exception', () async {
    // MetadataGod n'est pas initialise en test : l'erreur doit etre avalee.
    expect(await readLocalTags(file('casse.mp3', 3)), isNull);
  });
}
