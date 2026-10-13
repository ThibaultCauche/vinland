# Sécurité

## Signaler une faille

Ne pas ouvrir d'issue publique. Utiliser **Security > Report a
vulnerability** sur la page GitHub du dépôt (signalement privé), ou
écrire directement à Thibault.

## Modèle de menace : « cercle fermé »

Vinland est une app privée pour Thibault et ses amis, qui ont chacun un
compte sur son serveur Navidrome. Ce n'est pas un service public.

**Ce qu'on protège**

- La bibliothèque musicale et le NAS (pas de lecture, d'écriture ni de
  suppression par un inconnu).
- Les identifiants Navidrome de chaque ami.
- L'activité d'écoute de chacun (voir [confidentialité](docs/confidentialite.md)).
- La chaîne de mise à jour : une fausse mise à jour installerait du code
  chez tous les amis.

**Contre qui**

| Qui | Ce qu'il peut faire | Protection |
|---|---|---|
| Un inconnu qui trouve l'adresse `*.ts.net` du NAS | Appeler les services exposés par Funnel | Authentification de chaque service (Navidrome ; clés des services maison, renforcées en session 04 ; secret d'hôte du Jam, session 05). |
| Un inconnu qui décompile l'APK public | Lire tout ce qui est compilé dedans | Ne jamais compiler un secret qui donne un accès réel. Les clés des services maison y sont encore : à remplacer par une authentification par utilisateur (session 04). |
| Quelqu'un sur le même Wi-Fi | Lire le trafic en clair | HTTPS par Funnel ; HTTP en clair seulement vers le réseau local ou Tailscale (session 06). |
| Un ami (compte légitime) | Voir ce que les autres partagent, rejoindre un Jam | Partage soumis à consentement ; un ami ne peut pas prendre la main sur le Jam d'un autre (session 05). |
| Quelqu'un qui pirate le compte GitHub | Publier une fausse release | 2FA sur GitHub, releases signées et vérifiées par l'app (session 07). |

**Hors périmètre** : un appareil déjà compromis (root, logiciel espion), un
ami qui partage volontairement ses identifiants, la sécurité de Navidrome
et de Tailscale eux-mêmes.

Les mesures marquées « session NN » sont dans des PR séparées ; tant
qu'elles ne sont pas fusionnées, le risque correspondant reste ouvert.

## Secrets

Aucun secret dans le dépôt : `lib/config/*.dart` est gitignoré et
régénéré par la CI à partir des secrets GitHub Actions.

| Secret | Où il vit | Sert à |
|---|---|---|
| Keystore Android (`ANDROID_KEYSTORE_*`, `ANDROID_KEY_ALIAS`) | PC de Thibault + secrets GitHub | Signer l'APK. **Ne jamais la régénérer** (voir `CLAUDE.md`). |
| `DISCORD_FEEDBACK_WEBHOOK_URL` | Secrets GitHub | Envoyer les retours sur Discord. |
| `AVATAR_SERVICE_*`, `DOWNLOAD_WORKER_*`, `SHARE_INBOX_*` | Secrets GitHub + `.env` du NAS | Adresse et clé des services maison. |
| Clé de signature des releases (session 07) | Secret GitHub | Signer les fichiers de release. |
| Mots de passe Navidrome | Stockage sécurisé de chaque appareil | Connexion de chaque ami. |

### Rotation

À faire si un secret a fuité (commit, capture d'écran, APK public...) et
au moins une fois par an pour les clés des services maison :

1. Générer la nouvelle valeur sur son PC (jamais dans une conversation
   Claude ni dans un fichier du dépôt).
2. La mettre dans le `.env` du NAS et redémarrer le service concerné.
3. La mettre à jour dans **Settings > Secrets and variables > Actions** du
   dépôt (`gh secret set NOM` dans son propre terminal).
4. Publier une nouvelle version pour que l'app embarque la nouvelle valeur.
5. Pour un webhook Discord : le supprimer dans Discord et en créer un neuf.

Exception : **la clé Android ne tourne pas**. La changer obligerait chaque
ami à désinstaller l'app et à perdre ses données locales.
