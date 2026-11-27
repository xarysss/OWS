# Audit du projet OpenStack (Phase 2, ticket #3)

Objectif : vérifier, avant d'appliquer `openstack/tofu`, que le projet OpenStack peut porter le
cluster. **Terminé quand** le dimensionnement est validé contre les quotas.

Le rapport chiffré est produit par [`scripts/audit-openstack.sh`](../scripts/audit-openstack.sh) et
rangé dans [`audit-openstack-resultats.md`](audit-openstack-resultats.md).

## Contexte

OpenStack est l'instance tout-en-un Kolla-Ansible 2026.2 de `os-compute-6`
(voir [`openstack/kolla`](../openstack/kolla/README.md)). L'audit tourne sur le serveur, avec
`OS_CLOUD=ows` (identifiant d'application du projet) ou, à défaut, `/etc/kolla/admin-openrc.sh`.
Avec les droits admin, il lit en plus la capacité physique (hyperviseur, pools Cinder, IP libres
du réseau externe).

## Besoin à couvrir

Calculé depuis `openstack/tofu` et les gabarits réels du projet. Le script prend la taille réelle
des gabarits quand ils existent, avec un minimum de 3 vCPU / 8 Go (CP) et 4 vCPU / 12 Go (worker).

| Ressource | Validation (1 + 1) | HA (3 + 3) | Origine |
|---|---|---|---|
| Instances | 2 | 6 | `control_plane_count`, `worker_count` |
| vCPU | 7 | 21 | CP 3 vCPU, worker 4 vCPU |
| RAM | 22 Go | 66 Go | CP 8 Go, worker 14 Go (`ows.worker`) |
| Volumes | 3 | 9 | 1 disque système par VM + 1 volume Ceph par worker |
| Go de volumes | 180 | 540 | système 40 Go, Ceph 100 Go |
| IP flottantes | 5 | 5 | API, bastion, ArgoCD, Grafana, Vault |
| Réseaux / sous-réseaux / routeurs | 1 / 1 / 1 | 1 / 1 / 1 | `ows-net`, `ows-router` |
| Ports | 8 | 12 | nœuds, VIP, 3 MetalLB, routeur, DHCP |
| Groupes / règles de sécurité | 3 / 16 | 3 / 16 | `default`, `ows-k8s`, `ows-ingress` |
| Paires de clés | 1 | 1 | `ows` |

## Checklist

| # | Point | Commande | Attendu |
|---|---|---|---|
| 1 | Accès et services | `openstack token issue`, `catalog list` | Nova, Neutron, Glance, Cinder, Placement |
| 2 | Quotas | `openstack quota show --usage` | quota total ≥ besoin ci-dessus |
| 3 | Gabarits | `openstack flavor list --all --long` | `ows.cp` ≥ 3 vCPU / 8 Go, `ows.worker` ≥ 4 vCPU / 12 Go (boot sur volume) |
| 4 | Image | `openstack image list --long` | `ubuntu-24.04` active (cloud image Noble, qcow2) |
| 5 | Réseau externe | `openstack network list --external`, `subnet list --long` | `public`, pool d'IP réservé à OWS |
| 6 | IP flottantes libres | `openstack ip availability show public` | au moins 5 libres |
| 7 | allowed-address-pairs | extension + création réelle d'un port `ows-audit-port` | accepté (VIP kube-vip, MetalLB) |
| 8 | Stockage | `volume type list`, `volume service list`, `volume backend pool list --long` | `cinder-volume` up, ≥ 540 Go libres |
| 9 | Capacité physique (admin) | `hypervisor list --long` | 21 vCPU et 66 Go placables |
| 10 | Santé | `compute service list`, `network agent list` | tout up |
| 11 | Collisions | `network list`, `subnet list` | pas de `ows-*`, 10.20.0.0/24 libre |

Le test du point 7 crée puis supprime `ows-audit-net`, `ows-audit-subnet` et `ows-audit-port`
(rien d'autre). `LIVE_TEST=0` le remplace par la seule lecture des extensions.

## Lancer l'audit

```bash
export OS_CLOUD=ows                                    # projet ows (clouds.yaml)
export ADMIN_OPENRC=/etc/kolla/admin-openrc.sh         # facultatif : IP libres, pools, hyperviseur
cd /home/ows/OWS
scripts/audit-openstack.sh -o docs/audit-openstack-resultats.md            # HA 3 + 3
CP_COUNT=1 WORKER_COUNT=1 scripts/audit-openstack.sh                      # validation 1 + 1
```

`ADMIN_OPENRC` n'est lisible que par root : lancer alors en root avec
`PATH=/home/ows/.local/bin:$PATH OS_CLIENT_CONFIG_FILE=/home/ows/.config/openstack/clouds.yaml`.

Code de sortie 0 : rien de bloquant. Code 1 : au moins un point **BLOQUANT** (détail dans la synthèse
en tête du rapport). Les points « à faire » (gabarit ou image à créer, par exemple) ne bloquent pas.

## Si un point manque (tout-en-un, en admin)

Le projet `ows` a été créé lors du déploiement ; ces commandes servent de référence pour le recréer.

```bash
source /etc/kolla/admin-openrc.sh
openstack project create ows
openstack role add --project ows --user admin member
openstack quota set ows --instances 10 --cores 32 --ram 102400 --volumes 20 \
  --gigabytes 1000 --floating-ips 8 --ports 50 --secgroups 10 --secgroup-rules 100
openstack flavor create ows.cp     --vcpus 3 --ram 8192  --disk 0 --public
openstack flavor create ows.worker --vcpus 4 --ram 16384 --disk 0 --public
openstack image create ubuntu-24.04 --public --disk-format qcow2 --container-format bare \
  --file noble-server-cloudimg-amd64.img
openstack network create public --external --provider-network-type flat \
  --provider-physical-network physnet1
openstack subnet create public-subnet --network public --subnet-range 10.202.100.0/24 \
  --gateway <passerelle> --no-dhcp --allocation-pool start=<début>,end=<fin>
```

## Résultats

Audit du 2026-11-27 : [`audit-openstack-resultats.md`](audit-openstack-resultats.md).

**Dimensionnement validé contre les quotas** pour le cluster 3 + 3 : quotas, gabarits, image, réseau
externe, 25 IP flottantes libres, allowed-address-pairs accepté, 1,7 To libres dans Cinder, 110 Go de RAM
libres sur l'hyperviseur. Plage d'IP flottantes 10.202.136.100-130 sans conflit visible sur le réseau
(balayage ARP), réservation à faire confirmer par l'IUT. Quota d'IP flottantes sans marge (5 sur 5).
