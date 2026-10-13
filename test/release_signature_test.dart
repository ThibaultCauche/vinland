import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinland/services/release_signature.dart';

// Fixtures generees avec le vrai binaire minisign 0.11 et une cle de TEST
// jetable (sans rapport avec la cle des releases) :
//   minisign -G -W -p test.pub -s test.key
//   sha256sum vinland-windows-v9.9.9.zip vinland-android-v9.9.9.apk > SHA256SUMS
//   minisign -S -s test.key -m SHA256SUMS -t "vinland v9.9.9"
// Les tests verifient donc la compatibilite avec ce que release.yml produit,
// pas seulement avec notre propre code.
const _testPublicKey = '''
untrusted comment: minisign public key C9D5ACF97FD26865
RWRlaNJ/+azVyUeBsJJvZvOhUTvB8R5Q7w8CBWwP6UjtWzLOo44xZNTZ
''';

const _zipContent = 'contenu du zip de test\n';
const _apkContent = 'apk de test\n';

const _sums =
    '0da04b17776c0e4c1a0703883ef8a7dd15d47ad1df809cb9efb5556ec2639932  vinland-windows-v9.9.9.zip\n'
    '20aac220224e33344cc64f81aafb55558b543ef605a360e8b9979724911c537d  vinland-android-v9.9.9.apk\n';

const _sumsSignature = '''
untrusted comment: signature from minisign secret key
RURlaNJ/+azVyeh0M9tCi2KgXsiH2u2j//Syh5NuSmqxZoOUFQTk4YE/2M7G56i5k3dUTdkmU9Q+KKeQ4cj2p68uzQvJ2nFLkwk=
trusted comment: vinland v9.9.9
4xsH/NutJf6rZ1NtViKq8ROq4bj571Ak8HMMJFcAln/vgC+b7p0nj2xtWqqOR1aYyV39PPNf/xC58c8dtlOSAg==
''';

// Meme SHA256SUMS signe en mode historique (minisign -l : pas de prehachage).
const _legacySignature = '''
untrusted comment: signature from minisign secret key
RWRlaNJ/+azVyb7qNMPzyZu2n3RONbgRjHtw6JXK9xClc7XCwwWqQIh6rdO75S8Co3W8XXLbVx36MwtEZQUDZxF3l5xxON3I0AM=
trusted comment: vinland legacy
qD5K1+FQ4B+LMYzhL0H9ZNp9fnV1Q71sbNYOqAII5Yp4EV4jrnrOmBI7YbDJzEa7E+YK9+tKGFrN5ZlOGlAOBQ==
''';

// Meme SHA256SUMS signe par une AUTRE cle.
const _otherKeySignature = '''
untrusted comment: signature from minisign secret key
RUQQBQ2lV84q1qNiQk2yodSmPYtJflbHo8mS89a9a1iz5b5eYdMpvLI8Irzb95cftoZfewMbd8Dn1s08s1y8iBWiHiwx4h6Cww8=
trusted comment: x
DffHOcz1H9onZlPH+SQqxKsOo8z2e0lyWOYBK7NWhY751r018WXkmuHsFIq6r9MDN9YtLJj+zgJ+5THEG24MBg==
''';

Future<String> _verify({
  String asset = _zipContent,
  String name = 'vinland-windows-v9.9.9.zip',
  String sums = _sums,
  String signature = _sumsSignature,
  String publicKey = _testPublicKey,
}) =>
    verifyReleaseAsset(
      assetBytes: utf8.encode(asset),
      assetName: name,
      checksums: utf8.encode(sums),
      signatureFile: signature,
      publicKey: publicKey,
    );

Matcher _refused(String fragment) => throwsA(isA<ReleaseVerificationException>()
    .having((e) => e.message, 'message', contains(fragment)));

void main() {
  group('verifyReleaseAsset', () {
    test('accepte un zip publie par une release signee', () async {
      expect(await _verify(),
          '0da04b17776c0e4c1a0703883ef8a7dd15d47ad1df809cb9efb5556ec2639932');
    });

    test("accepte l'APK de la meme release", () async {
      await _verify(asset: _apkContent, name: 'vinland-android-v9.9.9.apk');
    });

    test('accepte une signature minisign historique (sans prehachage)',
        () async {
      await _verify(signature: _legacySignature);
    });

    test('refuse un zip modifie a la main', () async {
      expect(_verify(asset: '${_zipContent}virus'), _refused('ne correspond'));
    });

    test('refuse un SHA256SUMS modifie (empreinte remplacee)', () async {
      final forged = _sums.replaceFirst('0da04b', '1da04b');
      expect(_verify(sums: forged), _refused('Signature'));
    });

    test('refuse une release signee par une autre cle', () async {
      expect(_verify(signature: _otherKeySignature), _refused('autre clé'));
    });

    test('refuse un commentaire de confiance modifie', () async {
      final forged = _sumsSignature.replaceFirst('v9.9.9', 'v9.9.8');
      expect(_verify(signature: forged), _refused('Signature'));
    });

    test('refuse une signature absente ou vide', () async {
      expect(_verify(signature: ''), _refused('Signature'));
    });

    test("refuse un fichier qui n'est pas dans SHA256SUMS", () async {
      expect(_verify(name: 'vinland-windows-v1.0.0.zip'),
          _refused("n'est pas listé"));
    });

    test('refuse tout tant que la cle publique est vide', () async {
      expect(_verify(publicKey: ''), _refused('page de release'));
    });

    test('accepte la cle publique sous forme de ligne seule', () async {
      await _verify(
          publicKey:
              'RWRlaNJ/+azVyUeBsJJvZvOhUTvB8R5Q7w8CBWwP6UjtWzLOo44xZNTZ');
    });
  });

  group('downloadVerifiedAsset', () {
    test("refuse une release publiee sans SHA256SUMS (avant la signature)",
        () async {
      expect(
        downloadVerifiedAsset(
          assetUrl: 'https://example.invalid/vinland-windows-v9.9.9.zip',
          checksumsUrl: null,
          signatureUrl: null,
          client: MockClient((_) async => http.Response('', 404)),
        ),
        _refused("n'est pas signée"),
      );
    });
  });

  group('parseSha256Sums', () {
    test('lit le format texte et binaire de sha256sum', () {
      final sums = parseSha256Sums('${'A' * 64}  a.zip\r\n${'b' * 64} *b.apk\n'
          'ligne invalide\n');
      expect(sums, {'a.zip': 'a' * 64, 'b.apk': 'b' * 64});
    });
  });

  test('la cle publique embarquee, si renseignee, est au format minisign', () {
    if (kReleasePublicKey.isEmpty) return;
    expect(() => MinisignPublicKey.parse(kReleasePublicKey), returnsNormally);
  });
}
