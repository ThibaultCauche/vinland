import 'dart:io';

/// Dit si une URL de serveur peut etre utilisee sans chiffrement (http://,
/// ws://). Le clair n'est accepte que vers des adresses qui ne traversent
/// pas Internet a nu : le reseau Tailscale (100.64.0.0/10, deja chiffre par
/// WireGuard, et les noms MagicDNS *.ts.net), le reseau local (10/8,
/// 172.16/12, 192.168/16, lien local, noms .local/.lan/.home.arpa ou sans
/// point) et la machine elle-meme. Tout le reste doit passer en https://
/// (c'est le cas de Tailscale Funnel).
///
/// Verifie cote Dart parce qu'Android ne sait pas exprimer une plage d'IP
/// dans network_security_config.xml (uniquement des noms de domaine), et
/// pour appliquer la meme regle sous Windows.
bool isCleartextAllowed(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return false;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https' || scheme == 'wss') return true;
  if (scheme != 'http' && scheme != 'ws') return false;
  return isPrivateHost(uri.host);
}

/// Vrai pour un hote Tailscale, local ou de boucle locale (voir
/// isCleartextAllowed).
bool isPrivateHost(String rawHost) {
  final host = rawHost.toLowerCase();
  if (host == 'localhost') return true;
  final ip = InternetAddress.tryParse(host);
  if (ip == null) {
    if (!host.contains('.')) return true; // nom court du reseau local
    return host.endsWith('.ts.net') ||
        host.endsWith('.local') ||
        host.endsWith('.lan') ||
        host.endsWith('.home.arpa');
  }
  if (ip.isLoopback || ip.isLinkLocal) return true;
  final b = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv4) {
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        // 100.64.0.0/10 : plage CGNAT utilisee par Tailscale.
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
  }
  // IPv6 : adresses uniques locales fc00::/7, dont la plage Tailscale
  // fd7a:115c:a1e0::/48.
  return (b[0] & 0xfe) == 0xfc;
}
