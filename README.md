# OWS — Migration Kubernetes de Kubenstein

Projet SAE Cloud. L'entreprise OWS migre le cluster Kubernetes de son client **Kubenstein**
d'AWS EKS vers un cluster **kubeadm haute disponibilité** (1.30, puis mise à niveau en 1.31)
sur des VM **OpenStack** (Kolla-Ansible), hébergées sur le serveur `os-compute-6`.

Suivi des tâches : GitHub Project Kanban **OWS** (colonnes À faire / En cours / Fait),
un ticket par étape du plan, étiqueté par phase (`phase-0` à `phase-15`).

## Architecture cible

- 3 control planes (3 vCPU, 8 Go), etcd intégré, VIP d'API (kube-vip ou Octavia).
- 3 workers (4 vCPU, 12 à 16 Go), chacun avec un volume de 100 Go pour Ceph.
- Ubuntu 24.04, containerd, Cilium (CNI).
- GitOps avec ArgoCD (app-of-apps) : MetalLB, Ingress / Gateway API, Rook-Ceph,
  Vault + External Secrets, Prometheus / Grafana, Velero, EFK.

## Organisation du dépôt

| Dossier | Contenu |
|---|---|
| [`docs/`](docs/) | Documentation : installation, secrets, upgrade, coûts, RETEX, rendu |
| [`openstack/`](openstack/) | Infrastructure OpenStack en OpenTofu (réseau, sécurité, VM, volumes, VIP) |
| [`ansible/`](ansible/) | Préparation des nœuds et installation kubeadm |
| [`kubernetes/`](kubernetes/) | Configurations kubeadm, valeurs Cilium initiales, upgrade |
| [`gitops/`](gitops/) | ArgoCD : bootstrap et applications déployées par GitOps |
| [`scripts/`](scripts/) | Scripts d'outillage, de vérification et de redéploiement |

## Étapes du plan

| # | Étape | Terminé quand |
|---|---|---|
| 0 | Cadrage | Tableau rempli, premier push |
| 1 | Outils | `openstack token issue` réussit |
| 2 | Audit du projet OpenStack | Dimensionnement validé contre les quotas |
| 3 | Infra (OpenTofu) | VM joignables en SSH, destroy/apply rejouable |
| 4 | Validation 1+1 | 2 nœuds Ready, test réseau Cilium OK |
| 5 | HA 3+3 | 6 nœuds Ready, perte d'un CP tolérée |
| 6 | GitOps (ArgoCD) | Un commit déploie tout seul |
| 7 | Réseau (MetalLB, Ingress) | Service joignable par IP |
| 8 | Stockage (Rook-Ceph) | HEALTH_OK, PVC lié |
| 9 | Secrets (Vault + ESO) | Aucun secret en clair dans Git |
| 10 | Supervision | Tableau Grafana versionné |
| 11 | Sauvegarde (Velero) | Restauration testée |
| 12 | Bonus (EFK, appli démo) | Application en ligne via ArgoCD |
| 13 | Redéploiement complet | Une procédure unique, chronométrée |
| 14 | Upgrade 1.30 → 1.31 | Cluster en 1.31, applications saines |
| 15 | Rendu | Livrables dans le dépôt |

## Règles

- **Aucun secret dans Git** : `clouds.yaml`, mots de passe, jetons, clés, kubeconfig, état OpenTofu
  (voir [`.gitignore`](.gitignore)). Seuls des fichiers `*.example` aux valeurs factices sont versionnés.
- Toutes les ressources OpenStack sont préfixées `ows-` ; aucune action hors du projet du groupe.
- L'OpenStack partagé et ses conteneurs ne sont jamais modifiés : tout passe par l'API.
- Le code est poussé depuis le PC ; le serveur clone le dépôt public, sans jeton GitHub.
- Chaque tâche a son ticket au Kanban avant d'être commencée. Voir [CONTRIBUTING.md](CONTRIBUTING.md).
