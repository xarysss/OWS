# Guide d'installation de la plateforme OWS

Ce guide déploie de zéro le cluster Kubernetes OWS sur l'OpenStack de l'IUT : VM créées par OpenTofu, cluster installé par kubeadm, puis toute la plateforme livrée par ArgoCD depuis ce dépôt. Il se rejoue à l'identique après un `tofu destroy`.

## 1. Architecture

| Élément | Choix | Détail |
|---|---|---|
| VM | OpenTofu + provider OpenStack | Réseau `10.20.0.0/24`, routeur, groupes de sécurité, 1 port fixe par nœud |
| Nœuds | Ubuntu 24.04 | CP `.11-.13` (3 vCPU, 8 Go), workers `.21-.23` (4 vCPU, 12-16 Go, + volume Ceph 100 Go) |
| Kubernetes | kubeadm 1.30 puis 1.31 | etcd intégré (empilé sur les CP), containerd, cgroup systemd |
| VIP API | kube-vip (pod statique, ARP) | `10.20.0.10:6443`, IP flottante pour l'accès depuis os-compute-6 |
| CNI | Cilium | Remplace kube-proxy, VXLAN, Hubble |
| LoadBalancer | MetalLB L2 | Plage `10.20.0.200-223`, annoncée par les workers |
| Stockage | Rook-Ceph v1.15 | 3 OSD, classe `ceph-block` par défaut, S3 RGW |
| GitOps | ArgoCD, app-of-apps | `gitops/root-app.yaml` → `gitops/apps/` |
| Secrets | Vault HA (Raft) + External Secrets | Aucun secret dans Git |
| Supervision | kube-prometheus-stack | Tableau `OWS - Vue d'ensemble`, alertes OWS |
| Sauvegarde | Velero + Kopia | S3 hors cluster, quotidienne 7 j, hebdo 30 j |

Adresses MetalLB fixées : ArgoCD `.201`, Grafana `.202`, Vault `.203`, Hubble UI `.204`. Les trois premières ont une IP flottante (sortie `service_floating_ips` d'OpenTofu).

Arborescence du dépôt :

```
openstack/tofu/        VM, réseau, sécurité, volumes (OpenTofu)
scripts/               deploy-cluster.sh, vault-bootstrap.sh, etcd-snapshot.sh, node/*.sh
kubernetes/kubeadm/    InitConfiguration, JoinConfiguration, politique d'audit
kubernetes/kube-vip/   pod statique de la VIP
kubernetes/vault/      politiques Vault (HCL)
gitops/root-app.yaml   app-of-apps
gitops/apps/           une Application ArgoCD par composant (version du chart figée)
gitops/values/         values.yaml de chaque chart Helm
gitops/manifests/      CRD de configuration (pool MetalLB, ExternalSecret, tableau, Schedule)
docs/                  ce guide, secrets, upgrade, choix techniques
```

## 2. Prérequis sur le poste d'administration (os-compute-6)

Tout se lance depuis `/home/ows` sur os-compute-6, avec un utilisateur non root.

```bash
sudo dnf install -y git jq python3-pip
pip install --user python-openstackclient
# OpenTofu (paquet officiel)
curl -fsSL https://get.opentofu.org/install-opentofu.sh | sh -s -- --install-method rpm
# kubectl et Helm
curl -fsSLo ~/.local/bin/kubectl "https://dl.k8s.io/release/v1.30.14/bin/linux/amd64/kubectl" && chmod +x ~/.local/bin/kubectl
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

git clone https://github.com/xarysss/OWS.git && cd OWS
```

Identifiants OpenStack : télécharger `clouds.yaml` depuis Horizon (Identité > Identifiants d'application, nom `ows`) et le placer dans `~/.config/openstack/clouds.yaml` (`chmod 600`). Il ne va jamais dans le dépôt.

```bash
export OS_CLOUD=ows
openstack token issue          # doit répondre
openstack quota show           # vérifier vCPU, RAM, volumes, IP flottantes
openstack image list | grep -i ubuntu
openstack flavor list
openstack network list --external
```

Clé SSH : `~/.ssh/ows_ed25519` (+ `.pub`).

## 3. Créer les VM (phase 1 : 1 CP + 1 worker)

```bash
cd openstack/tofu
cp terraform.tfvars.example terraform.tfvars   # ajuster image, gabarits, réseau externe
tofu init
tofu plan
tofu apply
tofu output
```

L'apply écrit `scripts/cluster.env` et `scripts/ssh_config` (ignorés par Git). Test : `ssh -F ../../scripts/ssh_config ows-cp-1 hostname`.

Si l'apply échoue sur `allowed_address_pairs`, la politique du cloud l'interdit : demander à l'administrateur de l'autoriser pour le projet (kube-vip et MetalLB en dépendent).

## 4. Installer Kubernetes

```bash
cd ~/OWS
./scripts/deploy-cluster.sh prereqs     # swap, modules, sysctl, containerd, kubeadm 1.30
./scripts/deploy-cluster.sh init        # kube-vip + kubeadm init sur ows-cp-1
./scripts/deploy-cluster.sh join        # worker(s)
./scripts/deploy-cluster.sh cilium      # le nœud passe Ready
export KUBECONFIG=~/.kube/ows.conf
kubectl get nodes -o wide
```

Validation de la phase 1 :

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --brief
# Test réseau complet (≈ 5 min, crée puis supprime le namespace cilium-test)
cilium connectivity test       # CLI cilium : https://github.com/cilium/cilium-cli
```

Le `controlPlaneEndpoint` pointe sur la VIP dès la phase 1 : c'est ce qui permet de passer en HA sans réinstaller.

## 5. Passer en haute disponibilité (3 CP + 3 workers)

```bash
cd openstack/tofu
sed -i 's/^control_plane_count.*/control_plane_count  = 3/; s/^worker_count.*/worker_count         = 3/' terraform.tfvars
tofu apply           # ajoute 4 VM, ne touche pas aux 2 existantes
cd ~/OWS
./scripts/deploy-cluster.sh prereqs     # met aussi /etc/hosts à jour partout
./scripts/deploy-cluster.sh join        # 2 CP (clé de certificats régénérée) puis 2 workers
kubectl get nodes
```

Test de tolérance : éteindre `ows-cp-1` dans Horizon, vérifier que `kubectl get nodes` répond toujours (la VIP bascule en quelques secondes sur un autre CP) et que `etcdctl endpoint health` montre 2 membres sur 3. Rallumer.

## 6. Installer la plateforme (GitOps)

```bash
./scripts/deploy-cluster.sh argocd
kubectl -n argocd get applications -w
```

ArgoCD applique les Applications par vagues. Deux étapes demandent une action :

1. **Vault (vague 3)** : les pods restent `0/1` tant que Vault est scellé. Dès que `vault-0` est `Running` :
   ```bash
   ./scripts/vault-bootstrap.sh init        # une seule fois de toute la vie du cluster
   ./scripts/vault-bootstrap.sh configure
   ./scripts/vault-bootstrap.sh seed        # mot de passe Grafana, clés S3 Velero, webhook
   ```
   Détail et règles : [secrets-vault.md](secrets-vault.md).
2. **Velero** : renseigner `s3Url` et le bucket dans `gitops/values/velero.yaml` (cible S3 confirmée à l'audit), committer, pousser.

Accès :

| Service | URL | Identifiants |
|---|---|---|
| ArgoCD | `http://<IP flottante argocd>` | `admin`, mot de passe initial (voir sortie du script), à changer puis supprimer `argocd-initial-admin-secret` |
| Grafana | `http://<IP flottante grafana>` | Vault `secret/ows/grafana` |
| Vault | `http://<IP flottante vault>:8200` | jeton personnel (politique `ows-admin`) |
| Hubble UI | `http://10.20.0.204` (depuis le réseau interne) | aucun |

Critère de fin : toutes les Applications `Synced` et `Healthy`, `ceph status` en `HEALTH_OK`, un PVC de test `Bound`.

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
kubectl get pvc -A
```

## 7. Vérifications de recette

| Exigence du bon de commande | Commande / preuve |
|---|---|
| 3 CP + 3 workers, etcd intégré | `kubectl get nodes`, `kubectl -n kube-system get pods -l component=etcd` |
| Cilium | `cilium status`, test de connectivité |
| MetalLB | `kubectl get svc -A | grep LoadBalancer` : IP de la plage |
| Rook-Ceph | `ceph status` HEALTH_OK, PVC `ceph-block` lié |
| ArgoCD | un commit sur `gitops/values/*.yaml` est appliqué sans commande manuelle |
| Prometheus / Grafana | tableau « OWS - Vue d'ensemble de la plateforme » |
| Velero | `velero backup create test --include-namespaces demo`, suppression du namespace, `velero restore create --from-backup test` |
| Secrets | `git grep -iE 'password|secret_key|token'` ne renvoie que des références |
| Upgrade 1.31 | [upgrade-1.31.md](upgrade-1.31.md) |

## 8. Redéploiement complet

```bash
cd openstack/tofu && tofu destroy && tofu apply
cd ~/OWS && ./scripts/deploy-cluster.sh all
./scripts/vault-bootstrap.sh init && ./scripts/vault-bootstrap.sh configure && ./scripts/vault-bootstrap.sh seed
# Restauration des données applicatives
velero restore create --from-backup <dernière ows-daily>
```

Chronométrer cette procédure pour le rendu (objectif : moins d'une heure hors téléchargements).

## 9. Dépannage

| Symptôme | Cause probable | Action |
|---|---|---|
| `kubeadm init` bloque sur « waiting for the API » | VIP non portée | `crictl logs $(crictl ps --name kube-vip -q)`, vérifier `allowed_address_pairs` et `KUBE_VIP_INTERFACE` |
| Nœuds `NotReady` | Cilium absent ou en échec | `kubectl -n kube-system get pods -l k8s-app=cilium` |
| Service LoadBalancer `<pending>` | MetalLB pas encore synchronisé, ou pool plein | `kubectl -n metallb-system get ipaddresspool` |
| IP MetalLB injoignable | port worker sans allowed-address-pairs | `openstack port show ows-worker-1-port -c allowed_address_pairs` |
| OSD non créés | volume non vierge | `wipefs -a /dev/vdb` sur le worker (détruit le contenu) |
| Application ArgoCD `Degraded` en vague 4 | Vault scellé ou non configuré | `./scripts/vault-bootstrap.sh unseal` |
