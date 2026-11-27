# Upgrade du cluster de Kubernetes 1.30 à 1.31

Procédure validée en l'exécutant sur le cluster HA (3 CP + 3 workers). Durée constatée : à remplir (≈ 10 min par nœud).

## 1. Compatibilité vérifiée avant l'upgrade

| Composant | Version déployée | Compatible 1.31 | Source |
|---|---|---|---|
| kubeadm / kubelet / kubectl | 1.30.x | cible 1.31.x (une version mineure à la fois) | politique de version skew Kubernetes |
| containerd | 1.7 (Ubuntu 24.04) | oui | |
| Cilium | 1.16 | oui (1.27 à 1.31) | matrice Cilium |
| Rook | v1.15 | oui (1.26 à 1.31) | notes de version Rook |
| MetalLB | 0.14 | oui | |
| ArgoCD, Vault, ESO, kube-prometheus-stack, Velero | voir `gitops/apps/` | oui | |
| API kubeadm | `v1beta3` | acceptée (v1beta4 introduite en 1.31) | |

Vérifier aussi qu'aucune API supprimée en 1.31 n'est utilisée :

```bash
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis
```

## 2. Préparation (obligatoire)

```bash
export KUBECONFIG=~/.kube/ows.conf
kubectl get nodes                                   # tous Ready, tous en v1.30.x
kubectl get applications -n argocd                  # tous Synced / Healthy
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status   # HEALTH_OK

# Sauvegardes
./scripts/etcd-snapshot.sh                          # ~/ows-backups/etcd-<date>.db
velero backup create pre-upgrade-131 --wait

# Éviter que Ceph rééquilibre pendant les redémarrages de workers
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set noout
```

Annoncer la fenêtre de maintenance. Ouvrir le tableau Grafana « OWS - Vue d'ensemble » pendant toute l'opération.

## 3. Upgrade automatisé

```bash
./scripts/deploy-cluster.sh upgrade 1.31
```

Le script traite les nœuds un par un, dans cet ordre : `ows-cp-1`, `ows-cp-2`, `ows-cp-3`, puis les workers. Pour chaque nœud :

1. `kubectl drain` (les pods partent sur les autres nœuds ; Vault et Ceph gardent leur quorum car un seul nœud est absent).
2. Dépôt apt basculé sur `pkgs.k8s.io/core:/stable:/v1.31`, `kubeadm` mis à jour.
3. Premier CP : `kubeadm upgrade plan` puis `kubeadm upgrade apply v1.31.x` (met à jour l'API server, le controller-manager, le scheduler, etcd, CoreDNS). Autres nœuds : `kubeadm upgrade node`.
4. `kubelet` et `kubectl` mis à jour, image pause 3.10, redémarrage de containerd et du kubelet.
5. `kubectl uncordon`, attente du statut `Ready`. Pour un worker : attente de `HEALTH_OK` sur Ceph.

## 4. Upgrade manuel (équivalent, pour comprendre ou reprendre un échec)

Sur le poste d'administration :

```bash
kubectl drain ows-cp-1 --ignore-daemonsets --delete-emptydir-data
```

Sur le nœud (`ssh -F scripts/ssh_config ows-cp-1`) :

```bash
sudo sed -i 's/v1.30/v1.31/g' /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
apt-cache madison kubeadm | head -3                 # repérer 1.31.x-1.1
sudo apt-mark unhold kubeadm && sudo apt-get install -y kubeadm=1.31.x-1.1 && sudo apt-mark hold kubeadm
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.31.x                  # premier CP uniquement
# sudo kubeadm upgrade node                         # autres CP et workers
sudo apt-mark unhold kubelet kubectl && sudo apt-get install -y kubelet=1.31.x-1.1 kubectl=1.31.x-1.1 && sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload && sudo systemctl restart kubelet
```

Retour au poste d'administration :

```bash
kubectl uncordon ows-cp-1
kubectl get node ows-cp-1
```

Répéter pour chaque nœud, un seul à la fois.

## 5. Après l'upgrade

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout
kubectl get nodes -o wide                           # tous en v1.31.x
kubectl version
kubectl -n kube-system get pods                     # etcd, apiserver, CoreDNS à jour
cilium status
kubectl get applications -n argocd
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
velero backup create post-upgrade-131 --wait
```

Mettre le dépôt à jour pour qu'un redéploiement parte directement en 1.31 : dans `scripts/versions.env`, `K8S_MINOR="1.31"` et `K8S_UPGRADE_MINOR="1.32"` ; `PAUSE_IMAGE="registry.k8s.io/pause:3.10"`. Committer avec le message « Upgrade Kubernetes 1.31 ».

## 6. Retour arrière

Kubernetes ne prend pas en charge le retour à une version mineure inférieure. En cas d'échec :

- **Un nœud bloqué en cours d'upgrade** : relancer `kubeadm upgrade apply` (idempotent) ; les manifestes précédents sont sauvegardés dans `/etc/kubernetes/tmp/kubeadm-backup-manifests-*`.
- **Plan de contrôle cassé** : restaurer le snapshot etcd (`etcdutl snapshot restore`) sur les 3 CP avec les paquets 1.30, en suivant la procédure officielle « Restoring an etcd cluster ».
- **Cluster irrécupérable** : redéploiement complet (guide d'installation, section 8) en 1.30, puis `velero restore create --from-backup pre-upgrade-131`.

## 7. Journal d'exécution (à remplir pendant l'upgrade)

| Nœud | Début | Fin | Version | Remarque |
|---|---|---|---|---|
| ows-cp-1 | | | | |
| ows-cp-2 | | | | |
| ows-cp-3 | | | | |
| ows-worker-1 | | | | |
| ows-worker-2 | | | | |
| ows-worker-3 | | | | |
