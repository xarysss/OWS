# OpenStack tout-en-un (Kolla-Ansible 2026.2) sur os-compute-6

À lancer en root sur le serveur, dans l'ordre, console iDRAC disponible en secours.

| Script | Rôle |
|---|---|
| `00-clean-compute.sh` | Sauvegarde puis retire l'ancien rôle compute du cloud partagé (`CONFIRM=sortir-du-cloud`) |
| `01-prepare.sh` | Kolla-Ansible, `/etc/kolla`, mots de passe générés, VG `cinder-volumes` sur `/dev/sda` |
| `02-deploy.sh` | bootstrap-servers, prechecks, pull, deploy, post-deploy |

Reste à écrire : le projet `ows` (quotas, image, gabarits, réseau externe), qui demande une plage
d'IP flottantes libres sur le réseau partagé.

À vérifier avant le déploiement : `eno1` atteint bien le réseau local (un test ARP vers la passerelle
sans réponse tant que `eno1` appartenait à l'ancien pont `br-ex`).

Aucun de ces scripts n'a encore été exécuté avec succès sur le serveur.
