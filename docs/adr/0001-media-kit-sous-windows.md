# 0001 · media_kit sous Windows, just_audio ailleurs

**Statut** : acceptée (avant la 1.0)

## Contexte

`just_audio` + `audio_service` est le duo le plus solide sur Android
(notification, écran verrouillé, focus audio). Mais `just_audio` n'a
aucune implémentation native pour Windows (ni Linux).

## Décision

Deux moteurs derrière une même interface, `PlayerEngine`
(`lib/services/player_engine.dart`) :

- `JustAudioPlayerEngine` sur Android ;
- `MediaKitPlayerEngine` (libmpv) sur Windows.

Le choix est fait une seule fois dans `main.dart` selon la plateforme.
`AppState` et `VinlandAudioHandler` ne parlent qu'à l'interface.

## Conséquences

- Les deux moteurs doivent respecter le même contrat. Exemple déjà
  rencontré : le mélange de mpv réordonne sa playlist interne, alors
  `MediaKitPlayerEngine` retraduit l'index courant dans l'ordre d'origine
  comme le fait just_audio.
- Les buffers Android sont réglés à part (30 à 60 s) pour absorber la
  latence du tunnel.
- Un bug de lecture doit être vérifié sur les deux plateformes.
