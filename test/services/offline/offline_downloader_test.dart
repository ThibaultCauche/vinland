import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinland/services/offline/offline_downloader.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vinland_offline_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  OfflineDownloader downloaderFor(
    Future<http.StreamedResponse> Function(http.BaseRequest) handler,
  ) =>
      OfflineDownloader(client: MockClient.streaming((request, _) async {
        return handler(request);
      }));

  http.StreamedResponse audio(List<List<int>> chunks) => http.StreamedResponse(
        Stream.fromIterable(chunks),
        200,
        headers: {'content-type': 'audio/mpeg'},
      );

  test('ecrit le fichier complet et ne laisse pas de .part', () async {
    final downloader = downloaderFor((_) async => audio([
          [1, 2, 3],
          [4, 5],
        ]));
    final target = File('${dir.path}/music/a.mp3');
    expect(await downloader.fetchToFile('https://nas/stream', target), isTrue);
    expect(await target.readAsBytes(), [1, 2, 3, 4, 5]);
    expect(await File('${target.path}.part').exists(), isFalse);
  });

  test('erreur HTTP : rien sur le disque', () async {
    final downloader = downloaderFor(
        (_) async => http.StreamedResponse(Stream.fromIterable([]), 404));
    final target = File('${dir.path}/a.mp3');
    expect(await downloader.fetchToFile('https://nas/stream', target), isFalse);
    expect(await target.exists(), isFalse);
  });

  test('erreur Subsonic en JSON (200) : pas pris pour un fichier audio',
      () async {
    final downloader = downloaderFor((_) async => http.StreamedResponse(
          Stream.fromIterable([
            '{"subsonic-response":{"status":"failed"}}'.codeUnits,
          ]),
          200,
          headers: {'content-type': 'application/json'},
        ));
    final target = File('${dir.path}/a.mp3');
    expect(await downloader.fetchToFile('https://nas/stream', target), isFalse);
    expect(await target.exists(), isFalse);
  });

  test('coupure en plein telechargement : ni fichier ni .part', () async {
    final downloader = downloaderFor((_) async {
      final controller = StreamController<List<int>>();
      controller.add([1, 2, 3]);
      scheduleMicrotask(() {
        controller.addError(const SocketException('coupure'));
        controller.close();
      });
      return http.StreamedResponse(controller.stream, 200,
          headers: {'content-type': 'audio/mpeg'});
    });
    final target = File('${dir.path}/a.mp3');
    expect(await downloader.fetchToFile('https://nas/stream', target), isFalse);
    expect(await target.exists(), isFalse);
    expect(await File('${target.path}.part').exists(), isFalse);
  });

  test('reponse vide : refusee', () async {
    final downloader = downloaderFor((_) async => audio([]));
    final target = File('${dir.path}/a.mp3');
    expect(await downloader.fetchToFile('https://nas/stream', target), isFalse);
    expect(await target.exists(), isFalse);
  });

  test('URL vide (pas d\'identifiants) : refusee sans appel reseau', () async {
    var calls = 0;
    final downloader = downloaderFor((_) async {
      calls++;
      return audio([
        [1]
      ]);
    });
    expect(
        await downloader.fetchToFile('', File('${dir.path}/a.mp3')), isFalse);
    expect(calls, 0);
  });

  test('safeFileName ne garde que des caracteres surs', () {
    expect(
        OfflineDownloader.safeFileName('navidrome_abc-1'), 'navidrome_abc-1');
    expect(
        OfflineDownloader.safeFileName('../../etc/passwd'), '______etc_passwd');
    expect(OfflineDownloader.safeFileName(''), '_');
  });

  test('runPool : tout est traite, jamais plus de N a la fois', () async {
    var running = 0;
    var maxRunning = 0;
    final done = <int>[];
    await OfflineDownloader.runPool(List.generate(10, (i) => i), 3, (i) async {
      running++;
      if (running > maxRunning) maxRunning = running;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      done.add(i);
      running--;
    });
    expect(done..sort(), List.generate(10, (i) => i));
    expect(maxRunning, 3);
  });

  test('runPool : liste vide', () async {
    await OfflineDownloader.runPool(<int>[], 3, (_) async => fail('jamais'));
  });
}
