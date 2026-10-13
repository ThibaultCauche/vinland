import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vinland/services/streaming_import_service.dart';

/// Import d'une playlist exportee d'un service de streaming (Exportify,
/// Excel, JSON Spotify...) : ce que l'ecran d'import montre avant de
/// chercher les titres sur le NAS.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('vinland_import_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final file = File(p.join(dir.path, name))..writeAsBytesSync(bytes);
    return file.path;
  }

  Future<List<Map<String, String>>> csv(List<int> bytes) =>
      StreamingImportService.parseCsvStream(write('p.csv', bytes)).toList();

  group('CSV', () {
    test('le modele propose par l\'app se relit tel quel', () async {
      final rows = await csv(utf8.encode(StreamingImportService.csvTemplate));
      expect(rows, hasLength(5));
      expect(rows.first, {
        'title': 'Bohemian Rhapsody',
        'artist': 'Queen',
        'album': 'A Night at the Opera',
        'dateAdded': '2024-03-15',
      });
    });

    test('export Exportify : colonnes reconnues, premier artiste seulement',
        () async {
      final rows = await csv(utf8.encode(
        'Track URI,Track Name,Album Name,Artist Name(s),Added At\r\n'
        'spotify:track:1,"Under Pressure","Hot Space","Queen;David Bowie",'
        '2024-05-01T10:00:00Z\r\n',
      ));
      expect(rows.single['title'], 'Under Pressure');
      expect(rows.single['artist'], 'Queen');
      expect(rows.single['album'], 'Hot Space');
      expect(rows.single['dateAdded'], '2024-05-01T10:00:00Z');
    });

    test('virgules et guillemets doubles dans un champ entre guillemets',
        () async {
      final rows = await csv(utf8.encode(
        'title,artist\n"Hello, ""World""",Moi\n',
      ));
      expect(rows.single['title'], 'Hello, "World"');
    });

    test('BOM UTF-8, lignes vides et derniere ligne sans retour', () async {
      final rows = await csv([
        0xEF, 0xBB, 0xBF, //
        ...utf8.encode('Titre,Artiste\n\nÉté,Zaz\nNoël,Tino'),
      ]);
      expect(rows.map((r) => r['title']), ['Été', 'Noël']);
      expect(rows.last['artist'], 'Tino');
    });

    test('les lignes sans titre sont ignorees', () async {
      final rows = await csv(utf8.encode('title,artist\n,Personne\nA,B\n'));
      expect(rows.map((r) => r['title']), ['A']);
    });

    test('un export Excel en latin1 garde ses accents', () async {
      final rows = await csv(latin1.encode('titre,artiste\nCafé,Bénabar\n'));
      expect(rows.single['title'], 'Café');
      expect(rows.single['artist'], 'Bénabar');
    });

    test(
        'une grosse playlist ne sort plus de titres en « Ã© » '
        '(accent coupe entre deux blocs de lecture)', () async {
      // File.openRead lit par blocs de 64 Ko : on place le « É » de « Été »
      // a cheval sur la frontiere (1er octet en 65 535e position), comme
      // dans une vraie playlist de quelques milliers de titres.
      const header = 'title,artist\n';
      final filler = 'a' * (65535 - header.length - ',b\n'.length);
      final buffer = StringBuffer('$header$filler,b\n');
      for (var i = 0; i < 2000; i++) {
        buffer.write('Été $i,Hélène Ségara\n');
      }
      final rows = await csv(utf8.encode(buffer.toString()));
      expect(rows, hasLength(2001));
      expect(rows[1]['title'], 'Été 0');
      expect(rows.where((r) => r['title']!.contains('Ã')), isEmpty);
      expect(
          rows.skip(1).where((r) => r['artist'] != 'Hélène Ségara'), isEmpty);
    });

    test('fichier avec seulement l\'en-tete : aucun titre', () async {
      expect(await csv(utf8.encode('title,artist')), isEmpty);
      expect(await csv(utf8.encode('')), isEmpty);
    });
  });

  group('JSON', () {
    Future<List<Map<String, String>>> json(Object content) =>
        StreamingImportService.parseJsonFile(
          write('p.json', utf8.encode(jsonEncode(content))),
        );

    test(
        'export Spotify {tracks: [...]} avec un album objet : on affiche son '
        'nom, plus « {name: ...} »', () async {
      final rows = await json({
        'tracks': [
          {
            'name': 'Around the World',
            'artists': [
              {'name': 'Daft Punk'}
            ],
            'album': {'name': 'Homework'},
            'added_at': '2023-07-14T08:30:00Z',
          },
          {'name': 'Titre seul', 'artist': 'X', 'album': 'Y'},
          {'name': ''},
        ],
      });
      expect(rows, hasLength(2));
      expect(rows.first, {
        'title': 'Around the World',
        'artist': 'Daft Punk',
        'album': 'Homework',
        'dateAdded': '2023-07-14',
      });
      expect(rows.last['album'], 'Y');
    });

    test('API Spotify {items: [{track: ...}]}', () async {
      final rows = await json({
        'items': [
          {
            'added_at': '2022-01-02T00:00:00Z',
            'track': {
              'name': 'Get Lucky',
              'artists': [
                {'name': 'Daft Punk'}
              ],
              'album': {'name': 'Random Access Memories'},
            },
          },
          {
            'track': {'name': 'Sans artiste', 'artists': []},
          },
        ],
      });
      expect(rows.first['title'], 'Get Lucky');
      expect(rows.first['album'], 'Random Access Memories');
      expect(rows.first['dateAdded'], '2022-01-02');
      expect(rows.last['artist'], '');
    });

    test('liste simple et format {content: [...]}', () async {
      final list = await json([
        {'title': 'A', 'artist': 'B', 'album': 'C', 'dateAdded': '2021-03-04'},
        {'title': 'D', 'timestamp': 'hier'},
      ]);
      expect(list.first['dateAdded'], '2021-03-04');
      expect(list.last['dateAdded'], 'hier');

      final content = await json({
        'content': [
          {'title': 'E', 'artist': 'F'},
        ],
      });
      expect(content.single['title'], 'E');
    });

    test('format inconnu : liste vide', () async {
      expect(await json({'autre': 1}), isEmpty);
    });
  });
}
