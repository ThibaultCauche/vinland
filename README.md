# Vinland

Un lecteur de musique personnel : streaming des morceaux hébergés sur mon NAS, accessible depuis n'importe où, avec les fonctionnalités sociales d'un vrai service (playlists collaboratives, amis, découverte) qu'un simple client Navidrome n'offre pas.

## Pourquoi ce projet

Je voulais garder le contrôle de ma bibliothèque musicale (pas d'abonnement, pas de dépendance à un service tiers qui peut retirer un titre) tout en gardant une expérience aussi fluide qu'une app de streaming grand public, sur mobile comme sur desktop.

## Fonctionnalités

- Lecture en streaming depuis un serveur [Navidrome](https://www.navidrome.org/) auto-hébergé, accessible à distance via un tunnel sécurisé
- Bibliothèque : albums, artistes, recherche, playlists — y compris des **playlists collaboratives**
- Fonctionnalités sociales : profils d'amis, découverte des albums qu'ils écoutent
- **Import depuis une plateforme de streaming** : fait correspondre une playlist externe aux morceaux déjà présents sur le NAS (ou à défaut affiche les métadonnées réelles du titre, pas un simple "indisponible")
- Lecture Bluetooth avec gestion des appareils de confiance, file d'attente, thèmes personnalisables
- Mise à jour automatique de l'app (Android et Windows) via GitHub Actions

## Stack & architecture

- **Client** : Flutter (Android + Windows desktop depuis la même base de code), `provider` pour l'état, `media_kit`/`just_audio` pour la lecture audio selon la plateforme, `audio_service` pour les contrôles média système
- **Backend musical** : [Navidrome](https://www.navidrome.org/) (API Subsonic) sur un NAS auto-hébergé
- **Accès distant** : tunnel sécurisé (Tailscale Funnel) plutôt qu'un port exposé directement
- **CI/CD** : GitHub Actions (`.github/workflows/release.yml`) build et publie les binaires Android et Windows à chaque release

## Lancer le projet

```bash
flutter pub get
flutter run              # sur l'appareil/émulateur connecté
flutter run -d windows    # build desktop Windows
```

Le client a besoin d'un serveur Navidrome accessible (URL + identifiants renseignés au premier lancement) — ce n'est pas un projet qui tourne "out of the box" sans backend, puisque c'est justement tout l'intérêt : c'est mon serveur personnel.

## Ce que j'ai appris

- Faire cohabiter proprement deux moteurs de lecture audio différents selon la plateforme (Windows vs Android/iOS), `just_audio` n'ayant pas d'implémentation Windows mature au moment du projet.
- Concevoir l'UX autour de contenu "non téléchargé" : plutôt que de masquer un titre absent du NAS, afficher ses vraies métadonnées et proposer un chemin pour l'obtenir, au lieu d'un état inerte.
- Exposer un service auto-hébergé sur Internet sans ouvrir de port : tunnel applicatif plutôt que NAT/port forwarding classique.
