# Journal des modifications

Toutes les évolutions notables de Vinland sont notées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et
le projet suit le [versionnage sémantique](https://semver.org/lang/fr/).
Les versions jusqu'à 1.2.2 ont été reconstituées à partir des messages de
commit.

## [Non publié]

## [2.2.0] - 2026-10-14

Visuel animé sur Android, boutons dans la barre des tâches Windows,
écran télé prêt pour la Chromecast. Notes pour les amis :
[docs/release-notes/v2.2.0.md](docs/release-notes/v2.2.0.md).

### Ajouté
- Chromecast : écran télé Vinland à la place du « Default Media Receiver »
  de Google, avec la grille d'hexagones qui pulse, la pochette, le titre
  et les paroles synchronisées. S'active une fois le récepteur enregistré
  chez Google (voir `cast-receiver/README.md`) ; d'ici là, rien ne change.
- Android : visuel animé dans le mini lecteur et le grand lecteur : des
  vagues de lumière douces partent de la pochette sur les vraies basses
  (pas sur une intro au piano), calées sur le son du haut-parleur, et un
  cercle lumineux autour de la pochette s'allume avec la voix. Il prend
  la couleur de la pochette, couvre tout le grand lecteur et se coupe
  dans Paramètres > Lecture.
  Android demande une fois l'accès au son (« micro ») ; sans lui, le
  visuel respire tout seul. Réservé à Android : rien sur Windows, même dans
  une fenêtre étroite.
- Windows : boutons précédent, lecture/pause et suivant dans l'aperçu qui
  s'affiche au survol de l'icône Vinland dans la barre des tâches, comme
  Spotify.

### Modifié
- La couleur d'ambiance suit la couleur principale de la pochette plutôt
  qu'un petit détail coloré, s'affiche dès le lancement de l'app et est
  préparée d'avance pour les morceaux suivants.
- Android : les pochettes des deux morceaux suivants sont chargées
  d'avance, plus de case vide d'une seconde au changement de morceau.
- Les derniers boutons violets (« Arrêter » et « Retour à la soirée » du
  blind test, boutons des fenêtres de confirmation) passent au vert
  Vinland : le vert est maintenant la couleur par défaut de toute l'app.

## [2.1.1] - 2026-10-14

### Modifié
- Mode Soirée, blind test et bilan musical reprennent le style du reste de
  l'app : fond choisi dans Personnalisation, cartes grises et vert
  Vinland à la place de l'orange et des couleurs vives. Les réponses du
  blind test sont maintenant repérées par une lettre (A, B, C, D).

### Corrigé
- Chromecast : les titres téléchargés sur le téléphone passent maintenant
  sur la Chromecast (lus depuis le serveur). Avant, le blind test, qui
  pioche surtout dans les titres likés, n'arrivait pas à jouer l'extrait
  sur la télé.
- Chromecast : une coupure de connexion (téléphone qui perd le Wi-Fi un
  instant, mise en veille) ne fait plus repartir la musique sur le
  téléphone pendant qu'elle continue sur la télé : l'app reprend la main
  sur la Chromecast toute seule.

## [2.1.0] - 2026-10-14

Paroles synchronisées, playlists intelligentes, bilan musical, blind test,
Android Auto et Chromecast. Notes pour les amis :
[docs/release-notes/v2.1.0.md](docs/release-notes/v2.1.0.md).

### Ajouté
- Paroles synchronisées : bouton « Paroles » dans le lecteur (mobile) et la
  barre de lecture (PC). La ligne en cours est mise en avant et suit la
  musique, un tap sur une ligne y saute. Les paroles viennent de Navidrome
  (tags du fichier ou `.lrc` à côté), sinon de LRCLIB ; à défaut de
  minutage, le texte s'affiche simplement.
- Accueil : rangée « Playlists intelligentes » qui se remplissent toutes
  seules à partir de ta bibliothèque : Ajoutés ce mois-ci, Jamais écoutés,
  Tes classiques, Likés oubliés, À redécouvrir, et une par décennie
  (Années 80, Années 2000...). Elles se mettent à jour d'elles-mêmes ;
  « Ajouter à ma bibliothèque » en fait une vraie playlist.
- Bilan musical (« Ton année en musique ») depuis l'accueil, sur mobile et
  PC : minutes écoutées, artiste n°1, top titres, albums et genres, mois et
  jour records, premier titre de l'année, et « Écouter ton top ». L'app
  tient maintenant un journal des écoutes de l'appareil pour le bilan par
  année ; avant lui, « Depuis toujours » part des compteurs d'écoute.
- Récap de soirée : durée, DJ de la soirée et artiste le plus joué.
- Mode Soirée : blind test (menu de l'hôte > « Blind test »). Un extrait
  d'un titre de la bibliothèque passe sur l'enceinte, les invités
  choisissent parmi 4 réponses colorées sur leur téléphone. Plus on répond
  vite, plus on marque. Classement après chaque manche et podium final,
  aussi sur l'écran d'ambiance. La file de la soirée attend la fin du jeu.
  Demande le relais à jour sur le NAS.
- Android Auto : Vinland apparaît dans la voiture avec tes titres likés,
  tes écoutes de la semaine, un aléatoire, tes playlists et les nouveautés
  du NAS, plus la commande vocale (« Ok Google, mets … sur Vinland »).
- Chromecast : le menu « Périphériques » liste les Chromecast du Wi-Fi.
  Un tap envoie la musique sur la télé ou l'enceinte, au même endroit du
  titre ; la file, les boutons et le volume continuent de se piloter
  depuis l'app (téléphone et PC).

## [2.0.2] - 2026-10-14

### Ajouté
- Accueil : rangée « Humeur » sous « Ton mood » (Triste, Joyeux, Mélancolique,
  Énervé, Motivé, Romantique, Planant), tirée des tags Last.fm et ramenée
  aux titres de ta bibliothèque. Visible une fois la clé Last.fm configurée.

## [2.0.1] - 2026-10-13

Corrections trouvées en testant la 2.0 sur PC et téléphone, plus la radio
d'un titre et les moods.

### Ajouté
- « Lancer la radio » sur un titre (menu du lecteur, des titres likés et des
  titres sur PC) : joue le titre puis une trentaine de titres proches de ta
  bibliothèque.
- Accueil : section « Ton mood » (Chill, Rock, Rap, Électro, Pop, BO &
  classique) qui lance en aléatoire les titres du genre choisi.

### Corrigé
- Lecture : après une coupure (autre appli qui prend le son, réseau), un
  titre mp3 ne repart plus du début pendant que le compteur continue.
- Lecture aléatoire : lancer un titre d'une liste mélange maintenant toute la
  liste, pas seulement les titres placés après lui (la file restait vide en
  lançant le dernier titre).
- Recherche : un titre déjà sur le NAS dont l'artiste principal a un nom
  court (« Gotye/Kimbra », « Muse/… ») n'apparaissait plus comme lisible.
- Téléchargement : l'app attend maintenant toute la durée possible côté NAS.
  Un titre tout juste sorti n'est plus introuvable jusqu'au lendemain.
- Un like fait sur un autre appareil (ex. le PC) apparaît au prochain
  lancement, même pour un titre que l'appareil ne connaissait pas encore.
- Synchro complète (au plus une fois toutes les 6 h) : ta bibliothèque reste
  visible et lisible pendant qu'elle tourne, au lieu de se vider puis se
  remplir petit à petit.
- Mobile : supprimer une playlist demande maintenant confirmation, comme sur
  PC.

## [2.0.0] - 2026-10-13

Version du mode Soirée, et de tout ce qu'il a fallu remettre d'aplomb
avant : sécurité du Jam et des mises à jour, lecture sans blanc, cache
qui ne perd plus rien, code découpé et testé. Notes pour les amis :
[docs/release-notes/v2.0.0.md](docs/release-notes/v2.0.0.md).

### Ajouté
- Mode Soirée, extras : écran d'ambiance pour la télé (grande pochette sur
  un fond à ses couleurs, titre, qui l'a proposé, les 3 suivants, QR code
  pour rejoindre ; plein écran, Échap pour sortir) ; radio automatique
  quand la file est vide (titres similaires de Navidrome, sinon artistes
  proches selon Deezer présents sur le NAS, sinon même artiste, jamais un
  titre déjà passé dans la soirée) ; récap de fin de soirée gardé en
  playlist « Soirée du JJ/MM » avec qui a proposé quoi, à partager avec
  les amis ; pack hors-ligne pour télécharger une playlist à l'avance
  avec sa progression. Le relais dit maintenant qui a proposé le titre en
  cours (`now_playing.by`).
- Mode Soirée dans l'app (menu Jam > « Mode soirée ») : l'hôte lance une
  soirée, affiche un QR code plein écran, voit la file avec qui a proposé
  quoi, lance un titre ou met un veto, retire ou exclut un invité, change le
  code. Les invités scannent le QR (ou tapent le code), choisissent un
  pseudo, cherchent, proposent et votent. La file de la soirée passe
  toute seule sur le lecteur de l'hôte, sa propre file reprend quand elle
  est vide. Réglages : titres max par invité, votes activés ou non.
  Reconnexion automatique après une coupure, et « Revenir à la soirée »
  après un redémarrage. Un invité sans compte peut entrer depuis l'écran
  de connexion.
- Mode Soirée, côté relais : protocole hôte/invités (`docs/soiree-protocole.md`),
  code court + jetons signés, recherche en lecture seule dans Navidrome pour
  les invités sans compte, file équitable (alternance entre invités, votes,
  3 titres en attente max, pas de doublon), veto et bannissement par l'hôte,
  et un client en ligne de commande pour tester (`jam_relay/bin/party_cli.dart`).
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
- Chaque release publie `SHA256SUMS` et sa signature minisign
  `SHA256SUMS.minisig`.
- Dossier `services/` pour les services du NAS : `docker-compose.yml`
  (ports liés à `127.0.0.1`, volumes nommés), modèle `.env.example`,
  `README.md` (déploiement, routes Tailscale), Dockerfile générique pour les
  services Python.
- Job CI `services` : `ruff`, `pytest` quand un service a des tests, et
  validation du `docker compose`.
- Documentation : architecture, décisions d'architecture (ADR), sécurité,
  confidentialité, liens et badges dans le README.

### Modifié
- Identifiant Android inchangé (`com.example.vinland`) : la 2.0
  s'installe par-dessus la 1.2.2 comme une mise à jour normale, sans
  perdre les données (voir [ADR 0007](docs/adr/0007-garder-identifiant-android.md)).
- La synchro perso ne sonde plus le relais toutes les 20 s pour toujours :
  le délai double à chaque essai (jusqu'à 5 min) et repart à 20 s au retour
  dans l'app.
- Le relais Jam passe de `jam_relay/` à `services/jam-relay/`.
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
- La CI refuse toute remarque de `flutter analyze`, même « info » (91
  remarques historiques corrigées, règles `unawaited_futures`,
  `avoid_print`, `prefer_final_locals` et `always_declare_return_types`
  activées).
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
- La mise à jour automatique (Windows et Android) vérifie la signature de
  la release et l'empreinte du fichier téléchargé, et refuse avec un
  message clair un fichier modifié ou une release non signée.
- Sur Windows, la mise à jour extrait d'abord dans un dossier temporaire
  puis remplace toute l'installation (plus de fichiers orphelins d'une
  ancienne version) et revient à l'ancienne version si la copie échoue.
- Une vérification de mise à jour par heure au plus, et l'app attend la fin
  du blocage quand GitHub limite les requêtes (soirées derrière une même
  box).
- Les actions GitHub sont épinglées par SHA.

### Sécurité
- Jam : reprendre l'hébergement d'une session existante exige désormais le
  secret d'hôte remis par le relais à la création (protocole v2). Un ami qui
  connaît le code ne peut plus détourner la session ; un transfert d'hôte
  remet un nouveau secret au nouvel hôte.
- Synchro perso : l'identifiant ne se calcule plus à partir du pseudo. Il
  dérive d'un secret aléatoire propre au compte, partagé entre ses appareils
  par une playlist privée.
- Codes de Jam entre amis sur 16 octets aléatoires (au lieu de 6).
- Relais Jam : messages de 256 Ko max, 200 sessions, 50 participants par
  session, 1 000 connexions, ping toutes les 20 s, fermeture des connexions
  qui ne rejoignent rien en 30 s, journal sans contenu.
- Au premier lancement, l'app demande ce que tu partages avec tes amis
  (likes, écoutes récentes, titre en cours). Un nouveau compte ne partage
  plus rien par défaut ; un compte existant retrouve ses réglages
  actuels, à confirmer.

### Corrigé
- Plus de plantage possible si on quitte l'écran pendant une connexion à
  Navidrome, une recherche ou le choix d'un fichier à importer.
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
- Import de playlist : un fichier CSV de plusieurs milliers de titres ne
  donne plus de titres en « Ã© » (un accent coupé entre deux blocs de
  lecture faisait basculer tout le bloc en latin1).
- Import d'un export Spotify en JSON : l'album s'affiche par son nom, plus
  en « {name: ...} ».

### Supprimé
- Variante « compacte » des cartes d'album de la page artiste, qui n'était
  plus utilisée nulle part.

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

[Non publié]: https://github.com/ThibaultCauche/vinland/compare/v2.2.0...HEAD
[2.2.0]: https://github.com/ThibaultCauche/vinland/compare/v2.1.1...v2.2.0
[2.1.1]: https://github.com/ThibaultCauche/vinland/compare/v2.1.0...v2.1.1
[2.1.0]: https://github.com/ThibaultCauche/vinland/compare/v2.0.2...v2.1.0
[2.0.2]: https://github.com/ThibaultCauche/vinland/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/ThibaultCauche/vinland/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/ThibaultCauche/vinland/compare/v1.2.2...v2.0.0
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
