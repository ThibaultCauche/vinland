# Journal des modifications

Toutes les évolutions notables de Vinland sont notées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et
le projet suit le [versionnage sémantique](https://semver.org/lang/fr/).
Les versions jusqu'à 1.2.2 ont été reconstituées à partir des messages de
commit.

## [Non publié]

### Ajouté
- CI GitHub Actions sur chaque PR et chaque push sur `main` : formatage,
  analyse et tests de l'app, analyse et tests du relais Jam, couverture de
  tests en artefact.
- Script `tool/write_stub_config.sh` pour générer des `lib/config/*.dart`
  vides et lancer l'analyse et les tests sans les secrets.
- Premier test du relais Jam (un hôte crée la session, un ami la rejoint).
- Dependabot, modèles de PR et d'issue, ce journal.
- Clé d'API OpenSubsonic optionnelle côté service Navidrome (à la place du
  jeton md5), pour les versions de Navidrome qui la gèrent.
- Plus de blanc entre deux titres : le titre suivant est préchargé sur un
  second lecteur pendant les 20 dernières secondes du titre en cours.
- Fondu enchaîné réglable de 0 à 12 s (Paramètres > Lecture, désactivé par
  défaut), jamais entre deux pistes qui se suivent sur un même album (live,
  mix).
- Volume égalisé (ReplayGain, par titre ou par album) à partir des tags
  renvoyés par Navidrome (Paramètres > Lecture, désactivé par défaut).
- Jam : les appareils restent alignés sans micro-coupures. Horloge commune
  mesurée avec le relais (ping/pong), petits écarts rattrapés en accélérant
  ou ralentissant la lecture de 3 % au plus, seek seulement au-delà d'une
  seconde.
- Jam : réglage « Décalage audio » par appareil (casque ou enceinte
  Bluetooth en retard), réglable pendant l'écoute ; appui long dessus pour
  voir l'écart mesuré avec l'hôte.

### Modifié
- Une release ne part plus si la CI est rouge sur le commit tagué.
- Interne, sans changement visible : la lecture et la file d'attente
  quittent `AppState` pour `PlayerController` et `domain/queue.dart`
  (testés avec un faux moteur audio), les thèmes pour `ThemeController`
  et la navigation plein écran pour `OverlayNavigator`. `AppState` ne
  dépend plus d'aucun écran.
- Interne : le Jam et la synchro perso quittent `AppState` pour
  `JamController`, qui pilote la lecture à travers une interface et se
  teste à deux appareils avec un faux relais. `MusicService`,
  `NavidromeService`, `JamService` et `DiscoveryService` ne sont plus des
  singletons : ils sont créés une fois dans `main.dart` et injectés.
- Interne : les pages artiste, album, album Deezer, recherche,
  discographie et profil d'ami partagent leur logique entre mobile et
  Windows (`lib/features/`, testée sans NAS ni Deezer) ; les deux versions
  ne gardent que leur mise en page.
- Tout le code Dart est formaté avec `dart format`.
- Le jeton Subsonic n'est plus écrit sur le disque : le cache de
  bibliothèque, les albums, l'historique de recherche et la pochette
  épinglée ne gardent que des ids, et les URL sont reconstruites à la
  demande. Le sel change à chaque démarrage. Les anciens caches sont
  convertis au premier lancement.
- Le cache de bibliothèque quitte `Documents` (souvent synchronisé
  OneDrive) pour le dossier support de l'app.
- Les logs masquent les paramètres secrets des URL (`t=`, `s=`, `p=`,
  `apiKey=`...).
- Un nouveau serveur en `http://` n'est accepté que sur Tailscale ou le
  réseau local ; ailleurs, `https://` est exigé. Android passe par un
  `network_security_config.xml` explicite.
- La synchro de la bibliothèque récupère les titres par pages de 500
  (`search3`) au lieu d'un appel par album : quelques dizaines de requêtes
  au lieu de plus de mille. Si elle est interrompue, la bibliothèque
  précédente est gardée (au lieu d'une bibliothèque tronquée) et la synchro
  est retentée au lancement suivant.
- Les appels au serveur passent par un client Subsonic testé
  (`lib/data/subsonic/`) qui distingue les refus du serveur des coupures
  réseau, et ne réessaie que ces dernières.

### Supprimé
- Variante « compacte » des cartes d'album de la page artiste, qui n'était
  plus utilisée nulle part.

### Corrigé
- Une app tuée pendant une sauvegarde ou une synchro ne perd plus les
  titres hors ligne, les playlists locales, les épingles ni l'ordre des
  likes : écriture atomique avec copie de secours (`.bak`) rechargée si le
  fichier est abîmé, et données perso dans un fichier à part
  (`userdata_<compte>.json`) que la synchro de bibliothèque ne réécrit
  jamais. L'ancien fichier est découpé tout seul au premier lancement.
- Sur Windows, la page d'un album au titre court (« 99 ») n'affiche plus
  les titres d'un autre album dont le nom le contient (« 99 Nights »).
- Sur Windows, une playlist partagée par un ami s'ouvre même quand aucun
  de ses titres n'est sur votre NAS, comme sur mobile.
- Un like, un renommage ou une suppression de playlist refusé par le
  serveur n'est plus affiché comme réussi (Subsonic répond « 200 » même en
  cas d'erreur).
- Les grosses playlists (plusieurs centaines de titres) se mettent à jour :
  la liste part dans le corps d'une requête POST, plus dans une URL trop
  longue.
- Une coupure réseau ne crée plus de playlist miroir en double (likes,
  écoutes récentes, épingles, « en cours ») ni de titres en double dans une
  playlist.
- Synchro perso : « Reprendre ici » relance bien le titre sur cet appareil
  (il demandait à l'autre appareil de rejouer son propre titre).
- Jam : le changement de titre de l'hôte part tout de suite vers les
  participants au lieu d'attendre le battement suivant.

## [1.2.2] - 2026-10-08

### Corrigé
- Le lecteur se figeait après le 2e titre enchaîné (`loadAndPlay` attendait
  la fin du titre et le verrou `_autoContinuing` restait posé). Republication
  de la 1.2.1 après la purge de l'historique.

### Supprimé
- La bande originale d'Arcane embarquée dans les assets, et le code de
  lecture de fichiers audio intégrés à l'app. L'historique du dépôt a été
  purgé (1,1 Go retirés).

### Modifié
- Le vérificateur de mise à jour pointe vers le nouveau nom d'utilisateur
  GitHub.
- Vrai README à la place de celui de `flutter create`.

## [1.2.1] - 2026-10-08

Version retirée : son tag pointait sur l'ancien historique. Voir 1.2.2.

## [1.2.0] - 2026-09-16

### Ajouté
- Refonte du Jam : file d'attente partagée de l'hôte vers les participants,
  écoute à la demande sans hébergement explicite, transfert d'hébergement à
  un ami nommé, contrôle à distance depuis plusieurs appareils.
- Copie de la playlist d'un ami dans sa propre bibliothèque.

### Corrigé
- Présence des amis plus fiable (vrai hors-ligne, état « En cours » si
  l'ami est déjà dans le Jam).
- Réserve de bas de page et barre de défilement de la bibliothèque
  identiques sur tous les écrans.

## [1.1.13] - 2026-09-15

### Ajouté
- « Lire ensuite ».

### Corrigé
- Auto-update Windows : le script de mise à jour était tué en silence
  (`ProcessStartMode.detached`).
- Bouton lecture/pause désynchronisé au premier titre.
- La reprise Bluetooth relançait le titre précédent.

## [1.1.12] - 2026-09-15

### Corrigé
- Fuite de données entre comptes : likes et playlists qui changeaient de
  compte, playlist d'ami invisible.

### Sécurité
- Durcissement de la sécurité et nettoyage du code mort.

## [1.1.11] - 2026-09-14

### Corrigé
- Disparition des contrôles média Android (notification et écran de
  verrouillage).

## [1.1.10] - 2026-09-14

### Corrigé
- L'auto-update Windows échouait en silence.

### Ajouté
- Demande d'exemption d'optimisation de batterie sur Android.

## [1.1.9] - 2026-09-14

### Ajouté
- Partage de titre, d'album et de playlist (vers l'extérieur et via une
  boîte de réception).

### Corrigé
- L'ordre des titres likés se reperdait.

## [1.1.8] - 2026-09-14

### Ajouté
- Import de fichiers locaux vers le NAS.

### Corrigé
- File d'attente sur desktop et auto-updateur.

## [1.1.7] - 2026-09-13

### Ajouté
- Filet de sécurité contre le blocage en fin de titre.

### Corrigé
- La synchro perso bloquait tous les boutons.
- Fond transparent en overlay.

## [1.1.6] - 2026-09-13

### Ajouté
- Logo Vinland et visuel desktop retravaillé.

### Corrigé
- Blocage de la lecture automatique en réseau instable.

## [1.1.5] - 2026-09-13

### Ajouté
- Auto-update Android complet.

### Corrigé
- Détection de mise à jour sur desktop.

## [1.1.4] - 2026-09-13

### Ajouté
- File d'attente gérée par l'app.
- Vue album dédiée sur desktop, rapprochement titres/artistes centralisé.

### Corrigé
- Biais de lecture.

## [1.1.3] - 2026-09-12

Première version publiée par le workflow de release GitHub Actions.

### Ajouté
- Jam (écoute collaborative), avatars, playlists partagées,
  personnalisation.

### Corrigé
- Workflow de release : config locale générée depuis les secrets, runner
  `windows-2022`, build Windows via `cmd`.

## [1.0.0] - 2026-09-10

### Ajouté
- Première version : lecture depuis Navidrome, bibliothèque, page Amis,
  reprise auto Bluetooth, retours via Discord, auto-update Windows.

[Non publié]: https://github.com/ThibaultCauche/vinland/compare/v1.2.2...HEAD
[1.2.2]: https://github.com/ThibaultCauche/vinland/compare/v1.2.0...v1.2.2
[1.2.1]: https://github.com/ThibaultCauche/vinland/releases/tag/v1.2.1
[1.2.0]: https://github.com/ThibaultCauche/vinland/compare/v1.1.13...v1.2.0
[1.1.13]: https://github.com/ThibaultCauche/vinland/compare/v1.1.12...v1.1.13
[1.1.12]: https://github.com/ThibaultCauche/vinland/compare/v1.1.11...v1.1.12
[1.1.11]: https://github.com/ThibaultCauche/vinland/compare/v1.1.10...v1.1.11
[1.1.10]: https://github.com/ThibaultCauche/vinland/compare/v1.1.9...v1.1.10
[1.1.9]: https://github.com/ThibaultCauche/vinland/compare/v1.1.8...v1.1.9
[1.1.8]: https://github.com/ThibaultCauche/vinland/compare/v1.1.7...v1.1.8
[1.1.7]: https://github.com/ThibaultCauche/vinland/compare/v1.1.6...v1.1.7
[1.1.6]: https://github.com/ThibaultCauche/vinland/compare/v1.1.5...v1.1.6
[1.1.5]: https://github.com/ThibaultCauche/vinland/compare/v1.1.4...v1.1.5
[1.1.4]: https://github.com/ThibaultCauche/vinland/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/ThibaultCauche/vinland/compare/v1.0.0...v1.1.3
[1.0.0]: https://github.com/ThibaultCauche/vinland/releases/tag/v1.0.0
