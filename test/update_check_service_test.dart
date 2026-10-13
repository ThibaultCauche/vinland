import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinland/services/update_check_service.dart';

Map<String, dynamic> _release(String tag, {bool signed = true}) => {
      'tag_name': tag,
      'html_url': 'https://github.com/ThibaultCauche/vinland/releases/tag/$tag',
      'body': 'notes de release longues',
      'assets': [
        {
          'name': 'vinland-windows-$tag.zip',
          'browser_download_url': 'https://dl/vinland-windows-$tag.zip',
        },
        {
          'name': 'vinland-android-$tag.apk',
          'browser_download_url': 'https://dl/vinland-android-$tag.apk',
        },
        if (signed) ...[
          {
            'name': 'SHA256SUMS',
            'browser_download_url': 'https://dl/SHA256SUMS'
          },
          {
            'name': 'SHA256SUMS.minisig',
            'browser_download_url': 'https://dl/SHA256SUMS.minisig',
          },
        ],
      ],
    };

void main() {
  group('parseVersion', () {
    test('lit un tag prefixe de v', () {
      expect(UpdateCheckService.parseVersion('v1.2.3'), [1, 2, 3]);
    });

    test('ignore le numero de build et les suffixes', () {
      expect(UpdateCheckService.parseVersion('1.2.2+18'), [1, 2, 2]);
      expect(UpdateCheckService.parseVersion('v2.0.0-beta'), [2, 0, 0]);
    });

    test('retourne null sur un tag illisible', () {
      expect(UpdateCheckService.parseVersion('nightly'), isNull);
    });
  });

  group('isNewer', () {
    test('compare numeriquement et non alphabetiquement (1.10 > 1.9)', () {
      expect(UpdateCheckService.isNewer([1, 10, 0], [1, 9, 0]), isTrue);
    });

    test('une version egale ou plus ancienne ne declenche rien', () {
      expect(UpdateCheckService.isNewer([1, 2, 2], [1, 2, 2]), isFalse);
      expect(UpdateCheckService.isNewer([1, 2, 1], [1, 2, 2]), isFalse);
    });

    test('1.3 et 1.3.0 sont la meme version', () {
      expect(UpdateCheckService.isNewer([1, 3], [1, 3, 0]), isFalse);
      expect(UpdateCheckService.isNewer([1, 3, 1], [1, 3]), isTrue);
    });
  });

  group('updateInfoFromRelease', () {
    test('trouve le zip, l APK, SHA256SUMS et sa signature', () {
      final info = UpdateCheckService.updateInfoFromRelease(
          _release('v1.3.0'), [1, 2, 2])!;
      expect(info.windowsDownloadUrl, 'https://dl/vinland-windows-v1.3.0.zip');
      expect(info.androidDownloadUrl, 'https://dl/vinland-android-v1.3.0.apk');
      expect(info.checksumsUrl, 'https://dl/SHA256SUMS');
      expect(info.signatureUrl, 'https://dl/SHA256SUMS.minisig');
    });

    test('une release non signee n a ni empreintes ni signature', () {
      final info = UpdateCheckService.updateInfoFromRelease(
          _release('v1.3.0', signed: false), [1, 2, 2])!;
      expect(info.checksumsUrl, isNull);
      expect(info.signatureUrl, isNull);
    });
  });

  group('checkForUpdate', () {
    late DateTime now;
    late int calls;
    late http.Response Function() respond;

    UpdateCheckService service() => UpdateCheckService(
          now: () => now,
          currentVersion: () async => '1.2.2',
          client: MockClient((_) async {
            calls++;
            return respond();
          }),
        );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      now = DateTime.utc(2026, 10, 12, 20);
      calls = 0;
      respond = () => http.Response(jsonEncode(_release('v1.3.0')), 200);
    });

    test('pas plus d une requete GitHub par heure (soiree derriere une box)',
        () async {
      final first = await service().checkForUpdate();
      expect(first.info?.latestVersion, 'v1.3.0');

      now = now.add(const Duration(minutes: 30));
      final second = await service().checkForUpdate();
      expect(calls, 1);
      // Le dernier resultat reste affiche sans redemander a GitHub.
      expect(second.info?.latestVersion, 'v1.3.0');

      now = now.add(const Duration(minutes: 31));
      await service().checkForUpdate();
      expect(calls, 2);
    });

    test('le bouton des Parametres passe outre l intervalle', () async {
      await service().checkForUpdate();
      await service().checkForUpdate(force: true);
      expect(calls, 2);
    });

    test('un 403 de limite GitHub bloque jusqu a la fin de la fenetre',
        () async {
      final reset = now.add(const Duration(minutes: 20));
      respond = () => http.Response('rate limited', 403, headers: {
            'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
          });
      final limited = await service().checkForUpdate(force: true);
      expect(limited.rateLimited, isTrue);
      expect(limited.info, isNull);

      now = now.add(const Duration(minutes: 10));
      final stillLimited = await service().checkForUpdate(force: true);
      expect(stillLimited.rateLimited, isTrue);
      expect(calls, 1);

      now = now.add(const Duration(minutes: 11));
      respond = () => http.Response(jsonEncode(_release('v1.3.0')), 200);
      final ok = await service().checkForUpdate(force: true);
      expect(ok.rateLimited, isFalse);
      expect(ok.info?.latestVersion, 'v1.3.0');
    });

    test('un 403 garde la mise a jour deja connue', () async {
      await service().checkForUpdate();
      respond = () => http.Response('rate limited', 403);
      final limited = await service().checkForUpdate(force: true);
      expect(limited.rateLimited, isTrue);
      expect(limited.info?.latestVersion, 'v1.3.0');
    });

    test('aucune mise a jour si la release est la version installee', () async {
      respond = () => http.Response(jsonEncode(_release('v1.2.2')), 200);
      final result = await service().checkForUpdate();
      expect(result.info, isNull);
      expect(result.rateLimited, isFalse);
    });
  });
}
