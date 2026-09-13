# Vinland -- notes pour Claude Code

## Publier une nouvelle version (release Windows + Android)

1. Bump `version:` dans `pubspec.yaml` (ex: `1.1.5+7` -> `1.1.6+8` -- le nombre
   avant `+` doit suivre semver, celui apres `+` s'incremente toujours de 1).
2. Commit les changements en cours (features, fixes...) avec ce bump de version.
3. `git push origin main`
4. `git tag vX.Y.Z && git push origin vX.Y.Z` (le tag doit correspondre a la
   partie avant `+` de `version:`, prefixee de `v`).
5. Le workflow `.github/workflows/release.yml` se declenche automatiquement sur
   ce tag : il build Windows + Android et publie une Release GitHub avec
   `vinland-windows-vX.Y.Z.zip` et `vinland-android-vX.Y.Z.apk` en ~5-8 min.
6. Verifier : `gh run list -R Tibobg/vinland -L 1` puis
   `gh run watch <run-id> -R Tibobg/vinland --exit-status`, et enfin
   `gh release view vX.Y.Z -R Tibobg/vinland` pour confirmer les deux assets.

Une fois publiee, l'app la propose toute seule aux utilisateurs (verif au
lancement + au retour au premier plan) : auto-update complet sur Windows
(remplace l'exe et redemarre), telechargement + ouverture de l'installeur
systeme sur Android (l'utilisateur doit juste confirmer l'installation,
Android l'exige). Rien d'autre a faire cote distribution.

## Pieges connus sur ce pipeline (deja corriges, ne pas re-casser)

- **Runner Windows fige sur `windows-2022`** (pas `windows-latest`) dans
  `release.yml` : l'image la plus recente utilise un "Dev Drive" (D:, ReFS)
  qui declenche un bug CMake ("Cannot extract through symlink") sur
  l'archive native de `metadata_god`, plus un hard-error MSVC sur le flag
  `/await` deprecated de `permission_handler_windows`. `windows-2022` evite
  les deux.
- **`lib/config/*.dart`** (credentials.dart, discord_config.dart,
  avatar_config.dart, download_worker_config.dart) sont gitignores (secrets/
  URLs internes au NAS) et n'existent donc pas dans le checkout CI : le
  workflow les regenere a partir de secrets du repo GitHub avant chaque
  build (voir les etapes "Write local config files"). Si un nouveau fichier
  de ce type est ajoute en local, il faut aussi l'ajouter au workflow +
  creer le(s) secret(s) correspondant(s) sinon le build CI cassera avec des
  erreurs "getter isn't defined".
- **Secrets deja configures** sur le repo GitHub (Settings > Secrets and
  variables > Actions), pas besoin d'y retoucher sauf rotation :
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
  `DISCORD_FEEDBACK_WEBHOOK_URL`, `AVATAR_SERVICE_BASE_URL`,
  `AVATAR_SERVICE_API_KEY`, `DOWNLOAD_WORKER_BASE_URL`,
  `DOWNLOAD_WORKER_API_KEY`.
- **Cle de signature Android** : `C:\Users\thett\vinland-release-keystore\
  vinland-release.jks` (hors repo, gitignore, alias `vinland`). Ne JAMAIS la
  regenerer : une nouvelle cle casse la compatibilite de signature avec les
  APK deja installes chez les utilisateurs (Android refuse l'update, il
  faudrait desinstaller/reinstaller et perdre les donnees locales pour tout
  le monde).
- Commandes `gh secret set` avec un vrai secret en clair dans la commande
  (ou meme via redirection depuis un fichier contenant le secret) sont
  bloquees par le garde-fou securite de l'environnement -- c'est a
  l'utilisateur de les executer lui-meme dans son propre terminal.
