# jam-relay

Relais WebSocket pour l'ecoute synchronisee ("Jam") de Vinland. Service
independant de l'app Flutter et de Navidrome : il ne fait que rediffuser
l'etat de lecture envoye par l'hote d'une session a tous les autres
participants de cette session. Aucun acces a la musique, aux comptes ou au
NAS -- juste un pub/sub en memoire, par `sessionId`.

## Deployer sur le NAS (a cote de Navidrome)

1. Le relais est decrit dans `services/docker-compose.yml` avec les autres
   services (voir `services/README.md`) :

   ```bash
   cd services
   docker compose up -d --build jam-relay
   ```

2. Exposer `/jam` sur le **meme hostname Funnel** que Navidrome (pas besoin
   d'un nouveau nom de domaine/certificat) en routant ce chemin vers le port
   du relais, en plus de la route deja en place vers Navidrome :

   ```bash
   tailscale serve --bg --set-path=/jam http://127.0.0.1:8765/jam
   tailscale funnel --bg 443 on
   ```

   (Ajuste `--set-path`/le port si `tailscale serve` route deja Navidrome
   differemment chez toi -- l'idee est juste que `https://<ton-host>/jam`
   arrive sur ce conteneur, exactement comme `https://<ton-host>/rest/...`
   arrive deja sur Navidrome.)

3. Cote app, `NavidromeService.baseUrl` donne deja le hostname Funnel : le
   client Jam (`lib/services/jam_service.dart`) construit l'URL WebSocket en
   remplacant `https://` par `wss://` et en ajoutant `/jam` -- rien a
   configurer en plus.

## Tester en local avant de deployer

```bash
dart pub get
dart run bin/server.dart          # ecoute sur :8765 par defaut (variable PORT)
```

Depuis l'app, pointer temporairement le client Jam sur
`ws://<IP-locale-du-PC>:8765/jam` (meme reseau) pour valider avant
d'exposer via Tailscale.

## Protocole (v2)

Messages JSON sur `/jam`. Chaque message envoye par le relais porte `"v": 2`.

| Message client | Effet |
| --- | --- |
| `host` `{sessionId, username, hostSecret?}` | Cree la session (le relais repond `joined` avec un `hostSecret`), ou en reprend l'hebergement si `hostSecret` est le bon. Sinon : `error` « hebergement refuse ». |
| `join` `{sessionId, username}` | Rejoint en participant. |
| `state` | Hote seulement : rediffuse aux participants. |
| `command` | Participant seulement : transmis a l'hote. |
| `transfer_host` `{targetUsername}` | Hote seulement : cede la main ; le nouvel hote recoit un nouveau `hostSecret`. |

Le `sessionId` sert a rejoindre (il circule entre amis), le `hostSecret` sert
a piloter (il ne quitte pas les appareils de l'hote). La synchro perso fournit
son propre `hostSecret`, derive du secret du compte, pour que chaque appareil
du compte puisse reprendre la main (voir `lib/services/personal_sync_secret.dart`).

**Compatibilite** : les apps 1.2.x restent compatibles pour creer, rejoindre
et suivre un Jam. Seule la reprise de la synchro perso entre deux appareils
en 1.2.x est refusee par ce relais : mettre a jour l'app sur tous les
appareils (de toute facon, l'identifiant de synchro perso change).

## Limites

Reglables par variables d'environnement (valeurs par defaut entre
parentheses) : `MAX_MESSAGE_BYTES` (262144), `MAX_SESSIONS` (200),
`MAX_PEERS_PER_SESSION` (50), `MAX_CONNECTIONS` (1000),
`HANDSHAKE_TIMEOUT_SECONDS` (30), `PING_INTERVAL_SECONDS` (20).

Le journal (sortie d'erreur du conteneur) ne contient que des compteurs et
les refus, jamais d'identifiant de session ni de contenu.
