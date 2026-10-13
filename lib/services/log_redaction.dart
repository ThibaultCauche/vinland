import 'package:flutter/foundation.dart';

/// Parametres d'URL qui portent un secret : jeton/sel Subsonic (`t`, `s`),
/// mot de passe Subsonic en clair ou encode (`p`), cle d'API OpenSubsonic
/// (`apiKey`) et cles des services maison (`key`, `api_key`, `token`).
const _secretParams = ['t', 's', 'p', 'apiKey', 'api_key', 'key', 'token'];

final _secretParamPattern = RegExp(
  '([?&](?:${_secretParams.join('|')})=)[^&#\\s"\',)]*',
);

/// Masque les secrets d'une chaine destinee aux logs : `t=abcd...` devient
/// `t=***`. debugPrint reste actif en release (logcat Android, console
/// Windows), et les messages d'erreur reseau (ClientException,
/// SocketException...) recopient l'URL complete de la requete : sans ce
/// filtre, le moindre echec de pochette ecrivait un equivalent du mot de
/// passe dans les journaux.
String redactSecrets(String message) =>
    message.replaceAllMapped(_secretParamPattern, (m) => '${m[1]}***');

/// Remplace debugPrint par une version qui masque les secrets, pour tous
/// les appels existants d'un coup (y compris ceux des paquets tiers). A
/// appeler une fois au tout debut de chaque point d'entree Dart (main et
/// bluetoothResumeMain).
void installRedactingDebugPrint() {
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    original(message == null ? null : redactSecrets(message),
        wrapWidth: wrapWidth);
  };
}
