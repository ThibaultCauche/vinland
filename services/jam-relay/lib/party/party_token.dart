// Jetons de la soiree (voir docs/soiree-protocole.md, « Jetons et code »).
//
// Signes en HMAC-SHA256 avec une cle tiree au hasard au demarrage du relais :
// les soirees vivent en memoire, un redemarrage les efface de toute facon,
// donc inutile de persister la cle (et rien a configurer sur le NAS).
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Ce que porte un jeton : quelle soiree, quel membre, quel role, jusqu'a
/// quand. Le relais revalide toujours la soiree et le membre derriere (un
/// membre banni garde un jeton bien signe, mais il ne passe plus).
class PartyClaims {
  final String partyId;
  final String memberId;
  final String role; // 'host' ou 'guest'
  final int expiresAtMs;

  const PartyClaims({
    required this.partyId,
    required this.memberId,
    required this.role,
    required this.expiresAtMs,
  });

  bool get isHost => role == 'host';
}

class PartyTokenSigner {
  final Hmac _hmac;

  PartyTokenSigner(List<int> key) : _hmac = Hmac(sha256, key);

  /// Cle aleatoire de 32 octets : le cas normal en production.
  factory PartyTokenSigner.random() {
    final random = Random.secure();
    return PartyTokenSigner(List.generate(32, (_) => random.nextInt(256)));
  }

  String sign(PartyClaims claims) {
    final payload = utf8.encode(jsonEncode({
      'p': claims.partyId,
      'm': claims.memberId,
      'r': claims.role,
      'exp': claims.expiresAtMs,
    }));
    final mac = _hmac.convert(payload).bytes;
    return '${_b64(payload)}.${_b64(mac)}';
  }

  /// null si le jeton est mal forme, mal signe ou expire.
  PartyClaims? verify(String token, DateTime now) {
    final dot = token.indexOf('.');
    if (dot <= 0 || dot != token.lastIndexOf('.')) return null;
    final List<int> payload;
    final List<int> mac;
    try {
      payload = _unb64(token.substring(0, dot));
      mac = _unb64(token.substring(dot + 1));
    } catch (_) {
      return null;
    }
    if (!_constantTimeEquals(_hmac.convert(payload).bytes, mac)) return null;
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final claims = PartyClaims(
        partyId: json['p'] as String,
        memberId: json['m'] as String,
        role: json['r'] as String,
        expiresAtMs: json['exp'] as int,
      );
      if (now.millisecondsSinceEpoch >= claims.expiresAtMs) return null;
      return claims;
    } catch (_) {
      return null;
    }
  }

  static String _b64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _unb64(String text) =>
      base64Url.decode(base64Url.normalize(text));

  // Comparaison en temps constant : ne pas reveler, par le temps de reponse,
  // combien d'octets de la signature sont justes.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
