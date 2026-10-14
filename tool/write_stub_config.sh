#!/usr/bin/env bash
# Genere des lib/config/*.dart "vides" (memes constantes que les vrais
# fichiers, valeurs '') pour pouvoir lancer flutter analyze / flutter test
# sans les secrets. Ces fichiers sont gitignores : la CI les recree a chaque
# run, et en local on ne les ecrase jamais (les vrais contiennent les URLs
# et cles du NAS).
#
# Si un nouveau fichier de config est ajoute, l'ajouter ici ET dans les
# etapes "Write local config files" de release.yml.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p lib/config

ecrire() {
  local fichier="lib/config/$1"
  shift
  if [ -e "$fichier" ]; then
    echo "conserve : $fichier (existe deja)"
    return
  fi
  printf '%s\n' "$@" > "$fichier"
  echo "cree     : $fichier"
}

ecrire credentials.dart \
  "const String kNavidromeUrl = '';" \
  "const String kNavidromeUser = '';" \
  "const String kNavidromePass = '';"
ecrire discord_config.dart \
  "const String kDiscordFeedbackWebhookUrl = '';"
ecrire avatar_config.dart \
  "const String kAvatarServiceBaseUrl = '';" \
  "const String kAvatarServiceApiKey = '';"
ecrire download_worker_config.dart \
  "const String kDownloadWorkerServiceBaseUrl = '';" \
  "const String kDownloadWorkerServiceApiKey = '';"
ecrire share_inbox_config.dart \
  "const String kShareInboxBaseUrl = '';" \
  "const String kShareInboxApiKey = '';"
ecrire lastfm_config.dart \
  "const String kLastfmApiKey = '';"
