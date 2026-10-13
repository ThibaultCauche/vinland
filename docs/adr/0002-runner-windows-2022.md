# 0002 · Runner GitHub `windows-2022` pour les releases

**Statut** : acceptée

## Contexte

L'image `windows-latest` de GitHub Actions utilise un « Dev Drive » (D:,
ReFS). Deux casses en ont découlé :

- CMake échoue (« Cannot extract through symlink ») sur l'archive native
  de `metadata_god` ;
- MSVC refuse le drapeau `/await`, déprécié, utilisé par
  `permission_handler_windows`.

## Décision

Le job Windows de `release.yml` est figé sur `windows-2022`.

## Conséquences

- Les deux bugs sont évités sans patcher les dépendances.
- Quand `windows-2022` sera retiré par GitHub, il faudra soit que ces
  paquets soient corrigés, soit trouver un contournement. Le noter ici
  dans une nouvelle ADR.
- Rappelé dans `CLAUDE.md`, section « Pièges connus ».
