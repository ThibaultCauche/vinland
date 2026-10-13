# Vinland

[![CI](https://github.com/ThibaultCauche/vinland/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ThibaultCauche/vinland/actions/workflows/ci.yml)
[![Dernière version](https://img.shields.io/github/v/release/ThibaultCauche/vinland?label=version)](https://github.com/ThibaultCauche/vinland/releases/latest)
![Plateformes](https://img.shields.io/badge/plateformes-Android%20%7C%20Windows-1DB954)
![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter)

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
- **CI/CD** : GitHub Actions. `ci.yml` vérifie formatage, analyse et tests à chaque PR ; `release.yml` rejoue ces vérifications puis build et publie les binaires Android et Windows à chaque release

## Plateformes

| Plateforme | Statut |
|---|---|
| Android | Supportée (APK publié à chaque release) |
| Windows | Supportée (zip publié à chaque release, mise à jour automatique) |
| iOS, macOS, Linux, Web | **Non supportées** : les dossiers `ios/`, `macos/`, `linux/` et `web/` viennent du modèle `flutter create`, ils ne sont ni construits ni testés. |

## Documentation

- [Architecture](docs/ARCHITECTURE.md) : schéma, rôle de chaque service, flux d'une lecture, d'une synchro et d'un Jam.
- [Décisions d'architecture (ADR)](docs/adr/) : pourquoi le code est comme il est.
- [Sécurité](SECURITY.md) : modèle de menace, gestion et rotation des secrets, signaler une faille.
- [Ce que tes amis voient](docs/confidentialite.md) : la confidentialité en langage simple.
- [Journal des modifications](CHANGELOG.md).
- [`CLAUDE.md`](CLAUDE.md) : conventions de travail et procédure de release.

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
