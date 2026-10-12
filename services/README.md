# Services du NAS

Petits services maison qui tournent sur le NAS a cote de Navidrome. L'app
les joint via le hostname Tailscale Funnel du NAS ; aucun n'est expose
directement sur le reseau (ports lies a `127.0.0.1`).

| Service | Langage | Role | Client dans l'app |
|---|---|---|---|
| `jam-relay/` | Dart | Relais WebSocket de l'ecoute synchronisee (Jam) | `lib/services/jam_service.dart` |
| `avatar-server/` | Python | Photos de profil (Navidrome n'en gere pas) | `lib/services/avatar_service.dart` |
| `share-inbox/` | Python | Partages cibles d'un ami a un autre | `lib/services/share_inbox_service.dart` |
| `download-worker/` | Python | Telechargement des morceaux absents (Lidarr, spotdl, beets) et imports de fichiers locaux | `lib/services/download_worker_service.dart` |

Navidrome lui-meme reste gere a part ; un bloc commente dans
`docker-compose.yml` permet de le reprendre ici plus tard.

## Installer ou mettre a jour sur le NAS

```bash
cd vinland/services
cp .env.example .env        # premiere fois seulement, puis remplir .env
docker compose up -d --build
docker compose ps           # tout doit etre "running"
```

Mise a jour apres un changement du depot :

```bash
cd vinland && git pull
cd services && docker compose up -d --build
```

Les donnees (avatars, partages, etat du worker) sont dans des volumes
Docker nommes (`vinland_avatars`, `vinland_shares`, `vinland_downloads`) :
elles survivent aux reconstructions. La musique reste dans le dossier du NAS
indique par `MUSIC_DIR`.

**Premiere bascule depuis les anciens conteneurs** : arreter l'ancien
conteneur du service, recopier ses donnees dans le volume, puis lancer
celui-ci. Exemple pour les avatars (adapter le chemin de l'ancien dossier) :

```bash
docker compose create avatar-server
docker cp /chemin/ancien/avatars/. "$(docker compose ps -aq avatar-server)":/data/
docker compose up -d avatar-server
```

## Routes Tailscale

Chaque service est publie sous un chemin du meme hostname Funnel que
Navidrome. Garder les chemins deja configures sur le NAS (ils sont dans les
URL de `lib/config/*_config.dart`) ; seul le port cible change si besoin.
Exemple :

```bash
tailscale serve --bg --set-path=/jam http://127.0.0.1:8765/jam
tailscale serve --bg --set-path=/avatars-api http://127.0.0.1:8766
tailscale serve --bg --set-path=/share-inbox http://127.0.0.1:8767
tailscale serve --bg --set-path=/download-worker http://127.0.0.1:8768
tailscale funnel --bg 443 on
tailscale serve status      # verifier le resultat
```

## Configuration

Toutes les valeurs sensibles passent par `services/.env` (modele :
`.env.example`), jamais par le code. `docker compose` refuse de demarrer si
une cle d'API obligatoire est vide.

## Verifier avant une PR

```bash
ruff check services && ruff format --check services
(cd services/jam-relay && dart analyze && dart test)
docker compose -f services/docker-compose.yml --env-file services/.env.example config -q
```

La CI (job `services`) lance les memes commandes, plus `pytest` des qu'un
dossier `tests/` existe dans un service Python.

## Ajouter le code des services

Le code Python de `avatar-server`, `share-inbox` et `download-worker` n'est
pas encore dans le depot (il n'existait que sur le NAS). En le copiant ici :
ne jamais inclure de `.env`, de dossier `data/` ni de cle en dur ; les
`Dockerfile` fournis sont generiques et peuvent etre remplaces par ceux du
NAS.
