import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/services/cleartext_policy.dart';

void main() {
  test('http sur une adresse Tailscale reste permis', () {
    expect(isCleartextAllowed('http://100.101.102.103:30043'), isTrue);
    expect(isCleartextAllowed('http://100.64.0.1'), isTrue);
    expect(isCleartextAllowed('http://100.127.255.254'), isTrue);
    expect(isCleartextAllowed('http://nas.tail1234.ts.net:4533'), isTrue);
    expect(isCleartextAllowed('http://[fd7a:115c:a1e0::1]:4533'), isTrue);
  });

  test('http sur le reseau local reste permis', () {
    expect(isCleartextAllowed('http://192.168.1.20:4533'), isTrue);
    expect(isCleartextAllowed('http://10.0.0.5'), isTrue);
    expect(isCleartextAllowed('http://172.20.0.2'), isTrue);
    expect(isCleartextAllowed('http://nas.local:4533'), isTrue);
    expect(isCleartextAllowed('http://nas:4533'), isTrue);
    expect(isCleartextAllowed('http://localhost:4533'), isTrue);
  });

  test('http vers Internet est refuse (jeton en clair)', () {
    expect(isCleartextAllowed('http://musique.example.com'), isFalse);
    expect(isCleartextAllowed('http://100.128.0.1'), isFalse);
    expect(isCleartextAllowed('http://100.63.255.255'), isFalse);
    expect(isCleartextAllowed('http://172.32.0.1'), isFalse);
    expect(isCleartextAllowed('http://8.8.8.8'), isFalse);
  });

  test('https est toujours permis (Tailscale Funnel)', () {
    expect(isCleartextAllowed('https://nas.tail1234.ts.net'), isTrue);
    expect(isCleartextAllowed('https://musique.example.com'), isTrue);
  });

  test('une URL sans schema ou invalide est refusee', () {
    expect(isCleartextAllowed('100.101.102.103:30043'), isFalse);
    expect(isCleartextAllowed(''), isFalse);
    expect(isCleartextAllowed('ftp://nas.local'), isFalse);
  });
}
