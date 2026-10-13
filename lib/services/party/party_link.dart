// Lien d'invitation du mode Soiree, affiche en QR code par l'hote :
// vinland://soiree?relay=<url du relais>&code=<code> (voir
// docs/soiree-protocole.md, « Jetons et code »).

/// Alphabet des codes courts (sans 0/O ni 1/I/L), comme le relais.
const partyCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const partyCodeLength = 6;

class PartyInvite {
  final String relayUrl;
  final String code;
  const PartyInvite({required this.relayUrl, required this.code});

  Uri toUri() => Uri(
        scheme: 'vinland',
        host: 'soiree',
        queryParameters: {'relay': relayUrl, 'code': code},
      );

  @override
  String toString() => toUri().toString();

  /// Null si le texte n'est pas une invitation utilisable : un QR code
  /// peut contenir n'importe quoi (autre appli, page web), et un relais
  /// qui ne serait pas du WebSocket n'a aucune chance de repondre.
  static PartyInvite? tryParse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme != 'vinland' || uri.host != 'soiree') {
      return null;
    }
    final relay = normalizeRelayUrl(uri.queryParameters['relay'] ?? '');
    final code = normalizePartyCode(uri.queryParameters['code'] ?? '');
    if (relay == null || code == null) return null;
    return PartyInvite(relayUrl: relay, code: code);
  }
}

/// Code saisi a la main : majuscules, sans espaces ni tirets. Null s'il ne
/// peut pas etre un code du relais (evite un essai rate pour rien, le
/// relais en limite le nombre).
String? normalizePartyCode(String raw) {
  final code = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (code.length != partyCodeLength) return null;
  for (final char in code.split('')) {
    if (!partyCodeAlphabet.contains(char)) return null;
  }
  return code;
}

/// Adresse du relais acceptee seulement en ws:// ou wss:// et sans
/// identifiants dans l'URL (le QR code est visible de tous).
String? normalizeRelayUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  if (uri.scheme != 'ws' && uri.scheme != 'wss') return null;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}

/// Adresse du relais d'apres celle du serveur Navidrome : le relais est
/// expose sur le meme nom Funnel sous /jam (voir WebSocketJamService).
String? relayUrlFromServer(String? baseUrl) {
  if (baseUrl == null || baseUrl.isEmpty) return null;
  final ws = baseUrl
      .replaceFirst(RegExp(r'^https'), 'wss')
      .replaceFirst(RegExp(r'^http'), 'ws');
  return normalizeRelayUrl('$ws/jam');
}

/// Pochette servie par le relais (GET /jam/party/cover/<id>, jeton dans
/// l'en-tete Authorization) : les invites n'ont pas de compte Navidrome.
Uri partyCoverUri(String relayUrl, String coverId, {int size = 120}) {
  final relay = Uri.parse(relayUrl);
  final path = relay.path.endsWith('/')
      ? relay.path.substring(0, relay.path.length - 1)
      : relay.path;
  return relay.replace(
    scheme: relay.scheme == 'wss' ? 'https' : 'http',
    path: '$path/party/cover/${Uri.encodeComponent(coverId)}',
    queryParameters: {'size': '$size'},
  );
}
