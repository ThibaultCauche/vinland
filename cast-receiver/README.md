# Écran télé Vinland (récepteur Chromecast)

Page web que la Chromecast charge quand on diffuse depuis Vinland, à la
place du « Default Media Receiver » de Google : grille d'hexagones qui pulse
avec la musique, pochette, titre, paroles synchronisées.

- `index.html` : mise en page ; `receiver.js` : lecture (SDK Cast « CAF »),
  paroles, analyse du son et dessin de la grille.
- Publiée sur GitHub Pages par `.github/workflows/cast-receiver.yml` à
  chaque modification sur `main` : https://thibaultcauche.github.io/vinland/
- L'app lance ce récepteur si `kVinlandReceiverAppId`
  (`lib/services/cast/cast_receiver.dart`) est renseigné, sinon (ou s'il
  refuse de se lancer) celui de Google.

## Mise en service (une seule fois)

1. GitHub > dépôt vinland > Settings > Pages > Source : **GitHub Actions**,
   puis lancer le workflow « Recepteur Chromecast » (onglet Actions).
2. https://cast.google.com/publish : s'inscrire (5 $ une fois), « Add new
   application » > **Custom Receiver**, nom « Vinland », URL
   `https://thibaultcauche.github.io/vinland/`. Noter l'**Application ID**
   (8 caractères).
3. Tant que l'application n'est pas publiée, la Chromecast doit être
   déclarée dans la console (« Add new device », numéro de série au dos ou
   dans l'app Google Home) et redémarrée ; ou cliquer « Publish » pour
   s'en passer.
4. Mettre l'Application ID dans `kVinlandReceiverAppId`.

## Le son et les CORS

La grille ne suit vraiment la musique que si Navidrome autorise les requêtes
d'une autre origine (CORS) : le récepteur le vérifie au premier titre et,
sinon, garde une pulsation régulière plutôt que de risquer un son muet.
