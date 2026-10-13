# 0004 · Accès distant par Tailscale Funnel

**Statut** : acceptée

## Contexte

L'app doit joindre le NAS depuis n'importe où (4G, chez des amis) sans
demander à chaque ami d'installer un VPN, et sans ouvrir de port sur la
box.

## Décision

Navidrome et les services maison sont exposés par **Tailscale Funnel**
sur un seul nom d'hôte HTTPS (`*.ts.net`), chaque service sur son chemin
(`/rest`, `/jam`, ...) via `tailscale serve`.

## Conséquences

- Pas de port ouvert, certificat HTTPS fourni par Tailscale.
- Mais le nom d'hôte est **public** : n'importe qui qui le connaît peut
  atteindre les services. Leur sécurité repose donc sur leur propre
  authentification (sessions 04 et 05), pas sur le réseau. Voir
  [SECURITY.md](../../SECURITY.md).
- Le débit du tunnel en mobilité est limité : d'où le transcodage
  ([ADR 0006](0006-transcodage-192-kbps.md)) et les gros buffers.
- Sur le réseau local ou le VPN Tailscale, l'app peut utiliser une autre
  URL ; les URL de lecture sont recalculées avec l'URL courante.
