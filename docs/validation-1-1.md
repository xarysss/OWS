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

## Résultat (27/11/2026)

Déployé depuis os-compute-6 (utilisateur `ows`) sur les VM créées en phase 3. OpenTofu a
créé les 6 VM du 3+3 ; pour cette phase, `scripts/cluster.env` est réduit à `ows-cp-1` et
`ows-worker-1` (les 4 autres rejoignent en phase 5 avec le fichier complet). Durée de
`prereqs` + `init` + `join` + `cilium` : environ 6 minutes.

| Élément | Valeur |
|---|---|
| Nœuds | `ows-cp-1` (10.20.0.11, control-plane) et `ows-worker-1` (10.20.0.21, worker), `Ready` |
| Kubernetes | v1.30.14 (kubeadm), Ubuntu 24.04.5, noyau 6.8 |
| Runtime | containerd 2.2.1 (d'où la correction `sandbox` ci-dessus) |
| CNI | Cilium 1.16.6, tunnel VXLAN, `KubeProxyReplacement: True`, santé 2/2 |
| VIP API | 10.20.0.10 portée par kube-vip v0.8.9 sur `ows-cp-1` ; IP flottante 10.202.136.130 utilisée par le kubeconfig (pas besoin du tunnel) |
| Pods système | 16 pods `kube-system` Running/Completed, tous prêts |

Sortie de `./scripts/deploy-cluster.sh validate` :

```text
  OK    2/2 nœuds Ready
  OK    kubelet en v1.30.x sur tous les nœuds
  OK    ows-cp-1 porte le rôle control-plane
  OK    tous les pods kube-system Running/Completed
  OK    tous les conteneurs Ready
  OK    CoreDNS disponible
  OK    agent Cilium OK
  OK    santé Cilium : tous les nœuds joignables
  OK    kube-proxy absent (remplacé par Cilium)
  OK    bail kube-vip détenu (ows-cp-1)
  OK    API joignable via la VIP depuis ows-worker-1
  OK    déploiement web prêt
  OK    pod web planifié sur un worker (ows-worker-1)
  OK    pod client démarré sur ows-cp-1
  OK    pod -> pod inter-nœuds (10.244.1.12)
  OK    DNS + Service (web.ows-validation.svc.cluster.local)
  registry.k8s.io : échec
  ÉCHEC DNS externe stable (8 noms)
```

Le critère de la phase 4 est atteint : 2 nœuds Ready, pods système OK, pod de test joignable
depuis l'autre nœud par son IP et par le DNS de son Service.

### Point ouvert : un DNS amont refuse les requêtes

Le sous-réseau `ows-subnet` distribue `1.1.1.1` et `9.9.9.9` (défaut de
`openstack/tofu/variables.tf`). Depuis le réseau de l'IUT, `9.9.9.9` répond `REFUSED` à toutes
les requêtes (testé depuis os-compute-6 et depuis `ows-cp-1`), alors que `1.1.1.1` et le
résolveur local `10.255.255.200` répondent. CoreDNS répartit les requêtes entre les deux : une
résolution externe sur deux échoue dans les pods. Les nœuds eux-mêmes ne sont pas gênés
(systemd-resolved bascule sur l'autre serveur), d'où le succès des téléchargements d'images.

Correction (phase 3, code OpenTofu) : `dns_nameservers = ["1.1.1.1", "10.255.255.200"]`, puis :

```bash
tofu apply                                                   # met à jour le sous-réseau
for n in ows-cp-1 ows-worker-1; do ssh -F scripts/ssh_config $n sudo networkctl renew ens3; done
kubectl -n kube-system rollout restart deploy/coredns        # relit /etc/resolv.conf
./scripts/deploy-cluster.sh validate                          # le dernier contrôle doit passer
```
