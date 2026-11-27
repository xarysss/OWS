# Scripts

Lancés depuis `os-compute-6` (dans `/home/ows/OWS`, dépôt public cloné). Aucun secret en dur :
les valeurs viennent de `OS_CLOUD`, des fichiers générés par OpenTofu ou de Vault.

| Script | Rôle |
|---|---|
| `install-outils.sh` | Phase 1, en root sur os-compute-6 : utilisateur `ows`, client OpenStack, OpenTofu, Ansible, kubectl, Helm |
| `deploy-cluster.sh` | Orchestrateur : `prereqs`, `init`, `join`, `kubeconfig`, `cilium`, `argocd`, `status`, `upgrade 1.31`, `all` |
| `vault-bootstrap.sh` | Vault : `init`, `unseal`, `configure`, `seed` |
| `etcd-snapshot.sh` | Sauvegarde etcd avant upgrade |
| `versions.env` | Versions figées (Kubernetes, kube-vip, Cilium, ArgoCD) |
| `lib/common.sh` | Fonctions communes |
| `node/` | Exécutés sur les nœuds : `00` prérequis, `01` containerd, `02` paquets kube, `03` kube-vip, `10` init, `11` join, `90` upgrade |
| `cluster.env.example` | Modèle de `cluster.env`, généré par OpenTofu (non versionné, comme `ssh_config`) |

Convention pour les nouveaux scripts : Bash, `set -euo pipefail`, idempotents si possible.
