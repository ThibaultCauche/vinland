import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:http/http.dart' as http;

/// Cle publique minisign des releases Vinland : 2e ligne du fichier
/// `vinland.pub` genere par Thibault (`minisign -G`). La cle privee
/// correspondante n'existe que dans le secret GitHub `MINISIGN_SECRET_KEY`,
/// avec lequel release.yml signe le fichier SHA256SUMS de chaque release.
///
/// Id de cle 715BE221A9A7EB0D (genere le 13/10/2026). Ne pas la changer a la
/// legere : voir « Signature des releases » dans CLAUDE.md. Vide, l'app
/// refuserait toute mise a jour automatique. release.yml relit cette valeur
/// et refuse de publier une release dont la signature ne correspond pas a
/// cette cle.
const String kReleasePublicKey =
    'RWQN66epIeJbccJRD76fGODRHPsUV5CjPhBlMQCo3Jl8QsWi7ufYc9Ex';

/// Nom des deux fichiers publies avec chaque release (voir release.yml).
const String kChecksumsAssetName = 'SHA256SUMS';
const String kChecksumsSignatureAssetName = 'SHA256SUMS.minisig';

/// Erreur de verification, avec un message deja redige pour l'utilisateur.
class ReleaseVerificationException implements Exception {
  final String message;
  const ReleaseVerificationException(this.message);

  @override
  String toString() => message;
}

/// Cle publique au format minisign : "Ed" + identifiant (8 octets) + cle
/// ed25519 (32 octets), en base64.
class MinisignPublicKey {
  final List<int> keyId;
  final List<int> key;

  const MinisignPublicKey._(this.keyId, this.key);

  /// Accepte la ligne base64 seule ou le contenu complet de `vinland.pub`
  /// (avec la ligne "untrusted comment").
  factory MinisignPublicKey.parse(String text) {
    final line = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).firstWhere(
        (l) => l.isNotEmpty && !l.startsWith('untrusted comment'),
        orElse: () => '');
    final bytes = _decodeBase64(line, 'Clé publique de vérification invalide.');
    if (bytes.length != 42 || bytes[0] != 0x45 || bytes[1] != 0x64) {
      throw const ReleaseVerificationException(
          'Clé publique de vérification invalide.');
    }
    return MinisignPublicKey._(bytes.sublist(2, 10), bytes.sublist(10));
  }
}

/// Verifie une signature minisign (format de minisign 0.11 : "ED", message
/// prehache en BLAKE2b-512, ou l'ancien "Ed", message signe tel quel) ET sa
/// signature globale, qui couvre le commentaire de confiance : sans elle,
/// on pourrait recoller une vieille signature avec un autre commentaire.
Future<void> verifyMinisign({
  required List<int> message,
  required String signatureFile,
  required String publicKey,
}) async {
  const invalid = ReleaseVerificationException(
      'Signature de la mise à jour invalide : mise à jour refusée.');

  final pk = MinisignPublicKey.parse(publicKey);
  final lines = signatureFile
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trimRight())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.length < 4 ||
      !lines[0].startsWith('untrusted comment:') ||
      !lines[2].startsWith('trusted comment: ')) {
    throw invalid;
  }

  final sigBytes = _decodeBase64(lines[1], invalid.message);
  if (sigBytes.length != 74) throw invalid;
  final algorithm = String.fromCharCodes(sigBytes.sublist(0, 2));
  final keyId = sigBytes.sublist(2, 10);
  final signature = sigBytes.sublist(10);
  if (!_sameBytes(keyId, pk.keyId)) {
    throw const ReleaseVerificationException(
        'Mise à jour signée avec une autre clé que celle de Vinland : '
        'mise à jour refusée.');
  }

  final List<int> signed;
  if (algorithm == 'ED') {
    signed = (await const DartBlake2b().hash(message)).bytes;
  } else if (algorithm == 'Ed') {
    signed = message;
  } else {
    throw invalid;
  }

  final ed25519 = DartEd25519();
  final publicKeyObj = SimplePublicKey(pk.key, type: KeyPairType.ed25519);
  final ok = await ed25519.verify(signed,
      signature: Signature(signature, publicKey: publicKeyObj));
  if (!ok) throw invalid;

  final trustedComment = lines[2].substring('trusted comment: '.length);
  final globalSig = _decodeBase64(lines[3], invalid.message);
  if (globalSig.length != 64) throw invalid;
  final globalOk = await ed25519.verify(
      [...signature, ...utf8.encode(trustedComment)],
      signature: Signature(globalSig, publicKey: publicKeyObj));
  if (!globalOk) throw invalid;
}

/// Lit un fichier au format de `sha256sum` ("<hex>  <nom>", ou "<hex> *<nom>"
/// en mode binaire) en table nom -> empreinte hexadecimale minuscule.
Map<String, String> parseSha256Sums(String content) {
  final sums = <String, String>{};
  final pattern = RegExp(r'^([0-9a-fA-F]{64}) [ *](.+)$');
  for (final line in content.split(RegExp(r'\r?\n'))) {
    final match = pattern.firstMatch(line.trim());
    if (match == null) continue;
    sums[match.group(2)!.trim()] = match.group(1)!.toLowerCase();
  }
  return sums;
}

/// Verifie qu'un fichier telecharge est bien celui publie par la release :
/// la signature de SHA256SUMS doit etre valide pour [publicKey], puis
/// l'empreinte de [assetBytes] doit correspondre a la ligne [assetName].
/// Leve [ReleaseVerificationException] sinon. Retourne l'empreinte verifiee.
Future<String> verifyReleaseAsset({
  required List<int> assetBytes,
  required String assetName,
  required List<int> checksums,
  required String signatureFile,
  String publicKey = kReleasePublicKey,
}) async {
  if (publicKey.trim().isEmpty) {
    throw const ReleaseVerificationException(
        "Cette version de Vinland ne sait pas encore vérifier les mises à "
        "jour : installe la nouvelle version depuis la page de release.");
  }
  await verifyMinisign(
      message: checksums, signatureFile: signatureFile, publicKey: publicKey);

  final expected = parseSha256Sums(utf8.decode(checksums))[assetName];
  if (expected == null) {
    throw ReleaseVerificationException(
        "$assetName n'est pas listé dans les empreintes signées : "
        'mise à jour refusée.');
  }
  final actual = crypto.sha256.convert(assetBytes).toString();
  if (actual != expected) {
    throw const ReleaseVerificationException(
        'Le fichier téléchargé ne correspond pas à la release signée '
        '(fichier modifié ou corrompu) : mise à jour refusée.');
  }
  return actual;
}

/// Telecharge [assetUrl] et le verifie avec SHA256SUMS + sa signature.
/// Une release publiee sans ces deux fichiers est refusee : depuis la
/// version qui a introduit la verification, toutes les releases sont signees
/// par release.yml, une release qui ne l'est pas n'est donc pas normale.
Future<({Uint8List bytes, String sha256})> downloadVerifiedAsset({
  required String assetUrl,
  required String? checksumsUrl,
  required String? signatureUrl,
  http.Client? client,
}) async {
  if (checksumsUrl == null || signatureUrl == null) {
    throw const ReleaseVerificationException(
        "Cette release n'est pas signée : mise à jour refusée.");
  }
  final c = client ?? http.Client();
  try {
    Future<Uint8List> get(String url, Duration timeout) async {
      final response = await c.get(Uri.parse(url)).timeout(timeout);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw http.ClientException(
            'HTTP ${response.statusCode}', Uri.parse(url));
      }
      return response.bodyBytes;
    }

    final checksums = await get(checksumsUrl, const Duration(seconds: 30));
    final signature = await get(signatureUrl, const Duration(seconds: 30));
    final bytes = await get(assetUrl, const Duration(minutes: 5));
    final assetName = Uri.parse(assetUrl).pathSegments.last;
    final hash = await verifyReleaseAsset(
      assetBytes: bytes,
      assetName: assetName,
      checksums: checksums,
      signatureFile: utf8.decode(signature),
    );
    return (bytes: bytes, sha256: hash);
  } finally {
    if (client == null) c.close();
  }
}

List<int> _decodeBase64(String text, String error) {
  try {
    return base64.decode(text.trim());
  } on FormatException {
    throw ReleaseVerificationException(error);
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
