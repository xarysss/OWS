# Phase 4 : validation du cluster 1+1

Ticket : #5. Objectif : un cluster kubeadm Kubernetes 1.30 avec 1 control plane (`ows-cp-1`)
et 1 worker (`ows-worker-1`), Cilium en CNI (sans kube-proxy) et l'API derrière la VIP
kube-vip, dès cette phase. C'est cette VIP qui permet de passer en 3+3 (phase 5) sans réinstaller.

## Critère « terminé quand »

- 2 nœuds `Ready` en v1.30.x ;
- tous les pods de `kube-system` `Running` (CoreDNS, etcd, API, Cilium, kube-vip...) ;
- Cilium sain, kube-proxy absent ;
- un pod de test répond, depuis un autre nœud, par son IP et par le DNS de son Service.

## Procédure

Prérequis : VM créées par OpenTofu (phase 3), donc `scripts/cluster.env` et
`scripts/ssh_config` présents. Depuis le poste d'administration :

```bash
cd ~/OWS
./scripts/deploy-cluster.sh prereqs    # swap, modules, sysctl, containerd, kubeadm 1.30
./scripts/deploy-cluster.sh init       # kube-vip + kubeadm init sur ows-cp-1
./scripts/deploy-cluster.sh join       # ows-worker-1
./scripts/deploy-cluster.sh cilium     # les nœuds passent Ready
./scripts/deploy-cluster.sh validate   # contrôles ci-dessous, code retour 0 si tout passe
```

`kubectl` et `helm` sont installés dans `~/.local/bin` s'ils manquent.

## Ce que vérifie `validate`

`scripts/validate-cluster.sh`, rejouable tel quel en 3+3 :

| # | Contrôle | Comment |
|---|---|---|
| 1 | Nœuds | tous `Ready`, nombre = `cluster.env`, kubelet en v1.30.x, rôle control-plane sur les CP |
| 2 | Pods système | tous `Running`/`Completed` et conteneurs prêts dans `kube-system`, CoreDNS disponible |
| 3 | Cilium | `cilium-dbg status` OK, DaemonSet kube-proxy absent |
| 4 | VIP | bail `plndr-cp-lock` détenu par un CP, `https://VIP:6443/livez` répond depuis chaque worker |
| 5 | Charge de test | nginx sur un worker, client busybox épinglé sur `ows-cp-1` : pod → pod inter-nœuds (tunnel VXLAN), Service par son nom DNS, DNS externe |

Le namespace `ows-validation` est supprimé à la fin (`KEEP=1` pour le garder).

## Fiabilisation des scripts (revue de la phase 4)

| Problème | Correction |
|---|---|
| `helm --wait` sur Cilium ne rendait jamais la main : Hubble UI est un Service `LoadBalancer` et MetalLB n'est installé qu'en phase 7 | Hubble UI en `ClusterIP` au bootstrap ; ArgoCD remet les values complètes |
| Le poste d'administration n'avait pas forcément `kubectl` | installé dans `~/.local/bin` (version stable de `K8S_MINOR`) |
| L'IP flottante associée au port de la VIP ne répond pas sur toutes les configurations Neutron | `kubeconfig` teste l'IP flottante, sinon ouvre un tunnel SSH vers la VIP via le bastion (`deploy-cluster.sh tunnel`, port local 16443 ; `127.0.0.1` est déjà dans les certSANs) |
| `containerd` 2.x renomme `sandbox_image` en `sandbox` : l'image pause n'était plus forcée | `sed` compatible 1.7 et 2.x, et contrôle après écriture (aussi dans `90-upgrade-node.sh`) |
| Kubeconfig créé en 0644 puis restreint | créé directement en 0600 |
| `ssh_config` absent : erreurs SSH peu claires | arrêt immédiat avec un message explicite |

## Résultat

_À compléter après le déploiement (dépend des VM de la phase 3)._

| Élément | Valeur |
|---|---|
| Date | |
| Version Kubernetes | |
| Cilium | 1.16.6 |
| kube-vip | v0.8.9, VIP 10.20.0.10 |
| Sortie de `validate` | |
