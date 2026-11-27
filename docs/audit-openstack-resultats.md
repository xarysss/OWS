# Audit du projet OpenStack (2026-11-27 11:16)

Généré par `scripts/audit-openstack.sh` (ticket #3). Cible : **3 control plane + 3 workers**, CP 3 vCPU / 8 Go, worker 4 vCPU / 14 Go, disque système 40 Go, volume Ceph 100 Go par worker, 5 IP flottantes.

Projet : `e6be014bc7734c56957621cc51b5a827`, utilisateur : `8c8b28fb43db40c0a970e605d60806cc`.

## Synthèse

| Point | État | Détail |
|---|---|---|
| Services Nova/Neutron/Glance/Cinder | OK | OK |
| Quotas | OK | OK |
| Gabarit control plane `ows.cp` | OK | 3 vCPU / 8 Go |
| Gabarit worker `ows.worker` | OK | 4 vCPU / 14 Go |
| Image `ubuntu-24.04` | OK | active |
| Réseau externe `public` | OK | présent |
| IP flottantes libres | OK | 25 libres sur le réseau + 0 non associées, besoin 5 |
| allowed-address-pairs | OK | création d'un port avec paire acceptée |
| Capacité Cinder | OK | 1699 Go libres, besoin 540 Go |
| Capacité physique | OK | 110 Go de RAM libres (besoin 66), 124 vCPU placables à 4:1 (besoin 21) |
| Services Nova | OK | 3 actifs |
| Agents Neutron | OK | 2 actifs |

**Dimensionnement validé contre les quotas.**

## Services

- `identity` : présent
- `compute` : présent
- `network` : présent
- `image` : présent
- `block-storage` : présent
- `placement` : présent
- `load-balancer` : absent

## Quotas

État : le quota total doit couvrir le besoin du cluster ; « utilisé » inclut les ressources `ows-*` déjà créées.

| Ressource | Quota | Utilisé | Libre | Besoin | État |
|---|---|---|---|---|---|
| instances | 10 | 2 | 8 | 6 | OK |
| cores | 24 | 7 | 17 | 21 | OK |
| ram | 81920 Mo | 22528 Mo | 59392 Mo | 67584 Mo | OK |
| volumes | 10 | 0 | 10 | 9 | OK |
| gigabytes | 600 Go | 0 Go | 600 Go | 540 Go | OK |
| floating-ips | 5 | 5 | 0 | 5 | OK |
| networks | 100 | 1 | 99 | 1 | OK |
| subnets | 100 | 1 | 99 | 1 | OK |
| routers | 10 | 1 | 9 | 1 | OK |
| ports | 500 | 8 | 492 | 12 | OK |
| secgroups | 10 | 3 | 7 | 3 | OK |
| secgroup-rules | 100 | 16 | 84 | 16 | OK |
| key-pairs | 100 | 0 | 100 | 1 | OK |

## Gabarits (flavors)

| Nom | vCPU | RAM | Disque | Public |
|---|---|---|---|---|
| ows.cp | 3 | 8 Go | 40 Go | True |
| ows.worker | 4 | 14 Go | 40 Go | True |

## Images

| Nom | Statut | Format | Visibilité | Taille |
|---|---|---|---|---|
| ubuntu-24.04 | active | qcow2 | public | 592 Mo |

## Réseaux

Réseaux externes :

- `public` (db1ada04-0c42-4c0d-a6b9-75d27bf64460)
  - sous-réseau `public-v4` 10.202.0.0/16, pools [{'start': '10.202.136.100', 'end': '10.202.136.130'}]

Réseaux `ows-*` déjà présents : ows-k8s-net.

## IP flottantes

IP flottantes allouées au projet : 5.

- 10.202.136.102 → 10.20.0.201
- 10.202.136.124 → 10.20.0.202
- 10.202.136.105 → 10.20.0.10
- 10.202.136.116 → 10.20.0.203
- 10.202.136.107 → 10.20.0.11

Disponibilité du réseau externe : 6 utilisées sur 31, **25 libres**.
- public-v4 10.202.0.0/16 : 6/31

## allowed-address-pairs et sécurité des ports

- extension `allowed-address-pairs` : oui
- extension `port-security` : oui
- extension `router` : oui
- extension `extraroute` : oui
- extension `dns-integration` : oui
- extension `standard-attr-tag` : oui

Test réel : port `ows-audit-port` créé avec la paire [{'mac_address': 'fa:16:3e:b8:c7:99', 'ip_address': '10.99.0.192/27'}], puis supprimé.

## Stockage (Cinder)

Types de volume : `__DEFAULT__`.

- service `cinder-scheduler` sur os-compute-6 : up / enabled
- service `cinder-volume` sur os-compute-6@lvm-1 : up / enabled
- pool `os-compute-6@lvm-1#lvm-1` : 1699.07 Go libres sur 1699.07 Go

Volumes existants dans le projet : 0.

## Hyperviseurs (admin)

| Hôte | État | vCPU utilisés / total | RAM utilisée / totale |
|---|---|---|---|
| os-compute-6 | up | 4 / 32 | 14848 / 127891 Mo |

Nova applique ses ratios d'allocation (vCPU 4:1 et RAM 1:1 par défaut depuis 2023.1) via Placement.

## Plage d'IP flottantes sur le réseau de l'IUT

Pool Neutron : `10.202.136.100-10.202.136.130` (31 adresses) sur `public-v4` (10.202.0.0/16,
passerelle 10.202.255.254). Balayage ARP depuis `os-compute-6` (interface `ens1f0np0`, même segment),
le 2026-11-27 :

| Adresse | Répond | Propriétaire |
|---|---|---|
| 10.202.136.102, .105, .107, .116, .124 | oui, MAC `fa:16:3e:95:b1:c4` | IP flottantes du projet `ows` (OpenStack) |
| 10.202.136.120 | oui, même MAC | passerelle du routeur `ows` sur `public` |
| les 25 autres | non | libres |

Aucun équipement étranger à OpenStack ne répond dans la plage : pas de conflit visible. Un balayage
ARP ne voit que les machines allumées ; la réservation de la plage reste à faire confirmer par l'IUT.

## Remarques

- Le quota d'IP flottantes (5) est exactement le besoin (API, bastion, ArgoCD, Grafana, Vault) : aucune
  marge. Le passer à 8 si un service exposé s'ajoute (`openstack quota set ows --floating-ips 8`).
- Le gabarit worker fait 14 Go (plage visée 12-16 Go) : le besoin en RAM du 3 + 3 est donc de 66 Go.
- Les gabarits ont un disque de 40 Go, ignoré puisque les VM démarrent sur un volume Cinder.
- Au moment de l'audit, le projet contenait déjà le déploiement 1 + 1 en cours (`ows-worker-1` ACTIVE,
  `ows-cp-1` en ERROR « No valid host was found ») : les ressources `ows-*` apparaissent donc dans
  « utilisé ». L'erreur de `ows-cp-1` ne vient pas des quotas ni de la capacité, tous deux suffisants.
