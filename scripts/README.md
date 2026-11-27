# Scripts

Scripts d'outillage lancés depuis `os-compute-6` (dans `/home/ows`, dépôt public cloné).

Convention : `NN-verbe-objet.sh`, Bash, `set -euo pipefail`, aucun secret en dur
(utiliser `OS_CLOUD`, les variables d'environnement ou Vault).

| Script | Rôle |
|---|---|
| `01-installer-outils.sh` _(à venir)_ | Client OpenStack, OpenTofu, Ansible, kubectl, Helm |
| `02-auditer-openstack.sh` _(à venir)_ | Quotas, images, gabarits, réseaux, IP flottantes |
| `13-redeployer.sh` _(à venir)_ | Destruction et reconstruction complète, chronométrée |
