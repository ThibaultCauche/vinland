# 0006 · Transcodage mp3 192 kbps

**Statut** : acceptée

## Contexte

Sans paramètre, Navidrome envoie le fichier source, souvent en FLAC. Le
tunnel Tailscale en 4G/5G ne suit pas toujours : micro-coupures de plus en
plus fréquentes après quelques titres, jusqu'au plantage du lecteur.

## Décision

Lecture en streaming et téléchargements hors-ligne demandent tous les deux
`format=mp3&maxBitRate=192` (`NavidromeService.streamMaxBitRateKbps`,
`MusicService.offlineMaxBitRateKbps`).

## Conséquences

- Lecture stable en mobilité, fichiers hors-ligne plus légers.
- Qualité inférieure au lossless, inaudible pour l'usage visé (soirées,
  enceintes Bluetooth).
- Charge CPU de transcodage sur le NAS. Une option « haute qualité en
  Wi-Fi » pourra être ajoutée plus tard si besoin.
