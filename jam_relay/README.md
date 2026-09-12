# jam_relay

Relais WebSocket pour l'ecoute synchronisee ("Jam") de Vinland. Service
independant de l'app Flutter et de Navidrome : il ne fait que rediffuser
l'etat de lecture envoye par l'hote d'une session a tous les autres
participants de cette session. Aucun acces a la musique, aux comptes ou au
NAS -- juste un pub/sub en memoire, par `sessionId`.

## Deployer sur le NAS (a cote de Navidrome)

1. Construire et lancer le conteneur. Exemple a ajouter dans le
   `docker-compose.yml` existant du NAS, a cote du service Navidrome :

   ```yaml
   jam_relay:
     build: ./jam_relay   # ou une image que tu push sur un registre
     restart: unless-stopped
     ports:
       - "8765:8765"
   ```

   Ou en une commande, sans compose :

   ```bash
   docker build -t vinland-jam-relay ./jam_relay
   docker run -d --name vinland-jam-relay --restart unless-stopped -p 8765:8765 vinland-jam-relay
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
