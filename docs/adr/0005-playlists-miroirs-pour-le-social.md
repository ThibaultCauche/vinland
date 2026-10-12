# 0005 · Playlists miroirs pour les fonctions sociales

**Statut** : acceptée

## Contexte

Navidrome n'a ni amis, ni profils, ni « en cours d'écoute » partagé. On
voulait ces fonctions sans écrire ni héberger de serveur dédié.

## Décision

Chaque compte publie des **playlists Navidrome « miroirs »**, reconnues par
leur commentaire :

| Commentaire | Contenu |
|---|---|
| `vinland:likes-mirror` | Titres likés |
| `vinland:recent-plays` | Dernières écoutes |
| `vinland:now-playing` | Titre en cours (nom `Jam:<id>` quand on héberge un Jam) |
| `vinland:pinned-tiles:...` | Raccourcis épinglés de l'accueil (privée, synchro entre ses appareils) |
| `vinland:collab:...` | Sous-listes d'une playlist collaborative |

Une playlist publique est visible par tous les comptes du serveur. Tout
compte du serveur est considéré comme un ami (`MusicService.fetchFriends`).
Le partage se règle en rendant la playlist publique ou privée.

## Conséquences

- Aucun service en plus : tout passe par l'API Subsonic.
- Tous les comptes du serveur voient ce qui est public. Depuis la session
  08, rien n'est partagé sans le consentement explicite de l'utilisateur
  (voir [confidentialité](../confidentialite.md)).
- Ces playlists doivent être exclues partout où l'on liste les « vraies »
  playlists (`planPlaylistSync`, tests dédiés).
- Le « titre en cours » est republié toutes les 60 s ; au-delà de 2 min sans
  mise à jour, l'ami est affiché hors ligne.
