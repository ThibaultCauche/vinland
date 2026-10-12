import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/services/log_redaction.dart';

void main() {
  test('une erreur reseau de pochette ne recopie pas le jeton dans les logs',
      () {
    const message = 'ClientException: Connection reset, '
        'uri=http://100.1.2.3:30043/rest/getCoverArt.view?id=1&u=thibault'
        '&t=0123456789abcdef&s=Sel12345&v=1.16.1&c=vinland';

    final redacted = redactSecrets(message);

    expect(redacted, isNot(contains('0123456789abcdef')));
    expect(redacted, isNot(contains('Sel12345')));
    expect(redacted, contains('t=***'));
    expect(redacted, contains('s=***'));
    // Le reste reste lisible pour deboguer.
    expect(redacted, contains('getCoverArt.view?id=1&u=thibault'));
    expect(redacted, contains('&v=1.16.1&c=vinland'));
  });

  test('masque aussi mot de passe et cle d API', () {
    final redacted =
        redactSecrets('GET /rest/ping.view?p=enc:6d6470&apiKey=cle-secrete');
    expect(redacted, 'GET /rest/ping.view?p=***&apiKey=***');
  });

  test('ne touche pas un texte sans parametre secret', () {
    const message = 'SYNC NAVIDROME: 1200 tracks, version=1.2.2';
    expect(redactSecrets(message), message);
  });
}
