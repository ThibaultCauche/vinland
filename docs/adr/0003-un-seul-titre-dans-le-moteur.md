# 0003 · Un seul titre chargé dans le moteur audio

**Statut** : acceptée (remplace l'ancien chargement de toute la file)

## Contexte

Au départ, toute la file était confiée au moteur (playlist just_audio ou
mpv) avec son mélange natif. Résultats observés :

- le titre affiché ne correspondait plus au titre entendu après un
  mélange ;
- le premier titre de « Titres likés » revenait bien plus souvent que les
  autres à chaque fin de cycle ;
- les boutons suivant/précédent de la notification et du casque ne
  faisaient rien.

## Décision

La file d'attente vit en Dart, dans `AppState.queue`. Le moteur ne reçoit
jamais qu'**un seul** titre (`AppState._playSingle`). Suivant, précédent,
aléatoire et répétition sont gérés par `AppState`. Les commandes système
(notification, casque) passent par `customActionStream` pour atteindre la
même logique.

## Conséquences

- Un seul endroit décide de l'ordre : l'affichage est toujours juste.
- Entre deux titres, le moteur recharge une source : il peut y avoir un
  court blanc. Le préchargement et le fondu sont prévus en session 14.
- Le Jam et la synchro perso s'appuient sur ce même état Dart.
