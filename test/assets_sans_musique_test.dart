import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Le depot a embarque par erreur la BO d'Arcane (299 OGG, 1,1 Go, droits
// d'auteur) dans assets/music/, purgee ensuite de tout l'historique. La
// musique vient de Navidrome : aucun fichier audio ne doit revenir dans les
// assets, ni dans le depot public, ni dans l'APK.
void main() {
  test('aucun fichier audio dans assets/ (BO Arcane purgee, droits d\'auteur)',
      () {
    const audioExts = ['.ogg', '.mp3', '.flac', '.m4a', '.wav'];
    final audio = Directory('assets')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .where((path) => audioExts.any(path.toLowerCase().endsWith))
        .toList();
    expect(audio, isEmpty);
  });
}
