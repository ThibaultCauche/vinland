# 0007 · Garder l'identifiant Android `com.example.vinland`

**Statut** : acceptée (session 19, release 2.0)

## Contexte

L'app Android porte l'identifiant `com.example.vinland`, celui que
`flutter create` met par défaut. Le plan de la 2.0 proposait de passer à
un identifiant « propre » (par exemple `fr.thibault.vinland`) au moment de
la version majeure.

Pour Android, l'identifiant **est** l'app : en changer revient à publier
une autre application. Une 2.0 avec un nouvel identifiant ne remplacerait
pas la 1.2.2 installée chez les amis. Il faudrait :

- que chacun désinstalle l'ancienne et installe la nouvelle à la main
  (la mise à jour automatique ne peut pas le faire) ;
- se reconnecter, retélécharger tout le hors-ligne, refaire les réglages
  et l'apparence ;
- prévoir un export/import des données locales et une 1.x d'avertissement
  avant la 2.0.

## Décision

On **garde** `com.example.vinland` (`applicationId` et `namespace` dans
`android/app/build.gradle.kts`), avec la même clé de signature
(voir `CLAUDE.md`).

## Conséquences

- La 2.0 s'installe par-dessus la 1.2.2 comme n'importe quelle mise à
  jour : rien n'est perdu, la mise à jour automatique suffit.
- L'identifiant n'apparaît nulle part dans l'app ni sur Windows. Il ne se
  voit que dans les paramètres Android et ne gêne pas tant que l'app
  n'est pas publiée sur un store (le Play Store refuse `com.example.*`).
- Si l'app part un jour sur un store, il faudra changer d'identifiant à ce
  moment-là, avec l'export/import décrit plus haut. Cette ADR sera alors
  remplacée.
