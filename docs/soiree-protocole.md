# Mode Soirée : protocole hôte / invités

> Version du protocole : **1** (champ `v`). Session 16 (M4). L'interface de
> l'app arrive en session 17 ; ce document fait foi pour le relais
> (`jam_relay/lib/party/`) et pour le futur client de l'app.

## Idée générale

Un appareil **hôte**, branché à l'enceinte, joue la musique. Les **invités**
scannent un QR code, choisissent un pseudo et peuvent **chercher** dans le
catalogue, **proposer** des titres et **voter**. Ils n'ont pas de compte
Navidrome et ne streament rien : seul l'hôte lit l'audio.

Le relais (le même service que le Jam, sur le NAS) garde l'état de la
soirée en mémoire : membres, file des propositions, titre en cours. Il
applique les règles (file équitable, limites, doublons, bannissement) pour
que tous les invités voient la même file, même si l'hôte perd le réseau un
moment.

```
 invité ──┐                         ┌── Navidrome (lecture seule :
 invité ──┼── WebSocket /jam ── relais     recherche, fiche titre, pochette)
 hôte  ───┘   + HTTP /jam/party/cover/<id>
```

La soirée utilise la même connexion WebSocket que le Jam (`wss://<hôte
Funnel>/jam`) mais des messages à part, préfixés ou listés ci-dessous. Un
appareil peut ouvrir une connexion dédiée à la soirée ; c'est ce que fera
l'app (plus simple à fermer proprement).

## Rôles

| Rôle | Comment on l'obtient | Peut |
|---|---|---|
| hôte | `party_create` avec ses identifiants Navidrome (vérifiés par le relais) | tout ce que fait un invité, plus `now_playing`, `veto`, `kick`, `party_rotate_code`, `party_end` ; pas de limite de titres en attente |
| invité | `party_join` avec le code court (ou son jeton pour revenir) | `search`, `suggest`, `vote`, `party_leave` |

## Jetons et code

- **Code court** : 6 caractères parmi `ABCDEFGHJKMNPQRSTUVWXYZ23456789`
  (sans 0/O ni 1/I/L, faciles à dicter), soit environ 890 millions de
  combinaisons. Il sert seulement à **entrer** dans la soirée.
- **QR code** : `vinland://soiree?relay=<url du relais>&code=<code>`. L'URL
  du relais est l'adresse Funnel publique, sans identifiants.
- **Jeton** : renvoyé par `party_joined`, à garder par l'appareil pour
  revenir après une coupure (`party_join` avec `token`). Format :
  `base64url(json) "." base64url(HMAC-SHA256(json))`, où le json contient
  `p` (soirée), `m` (membre), `r` (`host` ou `guest`) et `exp` (fin de la
  soirée, en ms). La clé HMAC est tirée au hasard au démarrage du relais :
  un redémarrage invalide tous les jetons, ce qui est cohérent puisque les
  soirées sont en mémoire et disparaissent aussi.
- Un jeton n'est valable que pour sa soirée, jusqu'à la fin de celle-ci
  (6 h par défaut, `PARTY_TTL_HOURS`, 24 h maximum), et plus du tout si le
  membre a été banni.

## Sécurité

- **Créer une soirée exige un compte Navidrome** : `party_create` porte
  `auth: {u, t, s}` (jeton Subsonic md5, comme l'app) ou `auth: {u, apiKey}`.
  Le relais appelle `ping` sur Navidrome avec ces valeurs ; refus si
  Navidrome ne répond pas `ok`. Sinon n'importe qui sur Internet pourrait
  ouvrir une soirée et fouiller le catalogue. Le relais ne garde pas ces
  valeurs. (En développement seulement : `PARTY_ALLOW_ANON_HOST=1`.)
- **Recherche en lecture seule** : le relais interroge Navidrome avec son
  propre compte (`NAVIDROME_URL`, `NAVIDROME_USER`, `NAVIDROME_PASSWORD`,
  idéalement un compte dédié sans droits d'admin). Les réponses aux invités
  ne contiennent que `id`, `title`, `artist`, `album`, `durationMs`,
  `coverId` : jamais d'URL Navidrome, d'identifiant ni de jeton.
- **Pochettes** : `GET /jam/party/cover/<coverId>?size=<32..600>` avec
  l'en-tête `Authorization: Bearer <jeton>`. Le relais demande la pochette
  déjà redimensionnée à Navidrome et la renvoie telle quelle.
- **Limites de débit** par membre (seau à jetons) : recherche 5 d'affilée
  puis 1/s ; propositions 3 d'affilée puis 1 toutes les 10 s (pas de frein pour l'hôte) ; votes 10
  puis 2/s ; pochettes 30 puis 5/s. Codes faux : 5 essais par connexion
  (puis fermeture) et 60 essais ratés pour tout le relais, puis 1/s.
- **Bannissement** : `kick` avec `ban: true` invalide le jeton du membre et
  retire ses titres. Comme un invité banni peut revenir sous un autre
  pseudo s'il connaît le code, l'hôte peut changer le code
  (`party_rotate_code`) et afficher un nouveau QR.
- Messages de soirée limités à 8 Ko ; textes coupés (pseudo 30 caractères,
  recherche 100, champs de titre 200).

## Règles de la file

- **File équitable** : on alterne entre les membres. Tour 1 = la première
  proposition en attente de chaque membre, tour 2 = la deuxième, etc. Dans
  un même tour, le score des votes (somme des +1/-1) départage, puis
  l'ordre d'arrivée. Un invité qui arrive tard passe donc devant le
  troisième titre de quelqu'un d'autre.
- **Maximum en attente** : `maxPendingPerGuest` titres par invité (3 par
  défaut, 1 à 10, choisi par l'hôte à la création). L'hôte n'a pas de
  limite.
- **Doublons refusés** : un titre déjà dans la file, en cours, ou parmi les
  `recentHistory` derniers titres joués (20 par défaut) est refusé.
- **Votes** : `votesEnabled` (vrai par défaut). Faux : un `vote` est refusé
  (`forbidden`) et la file suit seulement l'ordre équitable.
- **Veto** : l'hôte retire un titre de la file.
- **Invités** : `maxGuests` (50 par défaut).
- Quand l'hôte lance un titre de la file (`now_playing` avec `itemId`), il
  quitte la file et devient le titre en cours.

## Messages

Tous les messages sont des objets JSON avec un champ `type`. Un champ
inconnu est ignoré (compatibilité ascendante). `party_create` et
`party_join` portent `v` ; si `v` est plus grand que la version du relais,
celui-ci répond `party_error` avec le code `version`.

### Client → relais

| type | qui | champs |
|---|---|---|
| `party_create` | futur hôte | `v`, `name` (soirée), `hostName`, `auth`, `rules?` {`maxPendingPerGuest`, `maxGuests`, `recentHistory`, `votesEnabled`} |
| `party_join` | invité | `v`, `code` + `name` ; ou `token` pour revenir |
| `search` | membre | `requestId`, `query` (2 à 100 caractères) |
| `suggest` | membre | `songId` ; sans catalogue côté relais, aussi `title`, `artist`, `album`, `durationMs`, `coverId` |
| `vote` | membre | `itemId`, `value` (1, -1 ou 0 pour retirer son vote) |
| `now_playing` | hôte | `itemId` (titre de la file) ou `songId` + infos + `by?` (titre hors file, `by` = étiquette affichée, par exemple « Radio », 40 caractères max), ou rien (arrêt) |
| `veto` | hôte | `itemId` |
| `kick` | hôte | `memberId`, `ban` (bool) |
| `party_rotate_code` | hôte | rien |
| `party_end` | hôte | rien |
| `party_leave` | membre | rien (l'invité garde le droit de revenir avec son jeton) |

### Relais → client

| type | à qui | champs |
|---|---|---|
| `party_joined` | celui qui entre | `v`, `partyId`, `memberId`, `role`, `token`, `name`, `rules`, `expiresAt` ; `code` pour l'hôte |
| `queue_state` | tous, à chaque changement | `items` [{`id`, `songId`, `title`, `artist`, `album`, `durationMs`, `coverId`, `by` (pseudo), `byId`, `score`, `myVote`, `mine`}] dans l'ordre de passage, `guestCount`, `hostOnline` ; pour l'hôte aussi `members` [{`id`, `name`, `online`, `pending`}] |
| `now_playing` | tous | `song` ({`songId`, `title`, ...} ou `null`), `itemId?`, `by` (pseudo de l'invité qui l'a proposé, étiquette de l'hôte, ou vide) |
| `suggested` | l'auteur | `itemId`, `songId` |
| `search_results` | le demandeur | `requestId`, `songs` [{`id`, `title`, `artist`, `album`, `durationMs`, `coverId`}] |
| `party_code` | hôte | `code` (après `party_rotate_code`) |
| `kicked` | le membre exclu | `banned` |
| `party_ended` | tous | `reason` (`host` ou `expired`) |
| `party_error` | l'émetteur | `code`, `message`, `requestId?` |

Codes d'erreur : `version`, `unauthorized` (identifiants refusés),
`bad_code`, `bad_token`, `expired`, `banned`, `full`, `forbidden` (action
réservée à l'hôte), `not_in_party`, `limit` (trop de titres en attente),
`duplicate`, `not_found`, `invalid`, `rate_limited`,
`search_unavailable`.

### Exemple

```
hôte   → {"type":"party_create","v":1,"name":"Anniv","hostName":"Thibault",
          "auth":{"u":"thibault","t":"<md5>","s":"<sel>"}}
relais → {"type":"party_joined","role":"host","code":"K7QX2M","token":"…", …}
invité → {"type":"party_join","v":1,"code":"K7QX2M","name":"Léa"}
relais → {"type":"party_joined","role":"guest","token":"…", …}
invité → {"type":"search","requestId":1,"query":"daft punk"}
relais → {"type":"search_results","requestId":1,"songs":[{"id":"s42", …}]}
invité → {"type":"suggest","songId":"s42"}
relais → {"type":"suggested","itemId":"i1","songId":"s42"}
relais → (à tous) {"type":"queue_state","items":[{"id":"i1","by":"Léa", …}], …}
hôte   → {"type":"now_playing","itemId":"i1"}
relais → (à tous) {"type":"now_playing","song":{"songId":"s42", …}}
```

## Durée de vie

- La soirée survit à une coupure de l'hôte (`hostOnline: false` pour les
  invités) ; l'hôte revient avec son jeton.
- Elle se termine par `party_end` ou à son expiration (vérifiée toutes les
  30 s) : `party_ended` puis fermeture des connexions de la soirée.
- Au plus 20 soirées en même temps sur le relais, 3 par compte Navidrome.

## Versionnage

- `v` = version **majeure** du protocole. Ajouter un champ ou un message ne
  change pas `v` : les clients ignorent ce qu'ils ne connaissent pas.
- Changer le sens d'un champ ou retirer un message fait passer à `v: 2`.
  Le relais refuse un client plus récent que lui (`version`) pour que l'app
  puisse dire « mets à jour le relais » au lieu de se comporter bizarrement.

## Dans l'app (session 17)

- `lib/controllers/party_controller.dart` : client du protocole (connexion
  dédiée, reconnexion avec le jeton, place gardée dans les préférences
  pour revenir après un redémarrage).
- `lib/controllers/party_host_dj.dart` : chez l'hôte, la tête de la file
  devient le prochain titre du lecteur (préchargement et fondu compris) ;
  chaque titre qui démarre est annoncé par `now_playing` (`itemId` s'il
  vient de la file, `songId` + infos sinon). File de soirée vide : la file
  de l'hôte reprend, pas de silence.
- Écrans dans `lib/screens/party/` ; entrée par le menu Jam, par le lien
  `vinland://soiree` (QR scanné avec l'appareil photo) ou par l'écran de
  connexion pour un invité sans compte. Un code tapé sans QR vise le relais
  du serveur de l'invité.
- Tests : `test/party/` branche la vraie logique du relais
  (`jam_relay/lib/party/`) en mémoire, sans réseau.

## Tester sans l'app

`jam_relay/bin/party_cli.dart` est un petit client en ligne de commande :

```bash
cd jam_relay
PARTY_ALLOW_ANON_HOST=1 dart run bin/server.dart       # terminal 1
dart run bin/party_cli.dart host ws://127.0.0.1:8765/jam  # terminal 2, affiche le code
dart run bin/party_cli.dart suggest ws://127.0.0.1:8765/jam <CODE> Léa <songId>
```

Contre le vrai relais, `host` demande `--user` et `--password` (le mot de
passe ne quitte pas la machine : seul le jeton md5 est envoyé).
