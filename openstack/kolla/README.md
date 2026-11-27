# OpenStack tout-en-un (Kolla-Ansible 2026.2) sur os-compute-6

À lancer en root sur le serveur, dans l'ordre, console iDRAC disponible en secours.

| Script | Rôle |
|---|---|
| `00-clean-compute.sh` | Sauvegarde puis retire l'ancien rôle compute du cloud partagé (`CONFIRM=sortir-du-cloud`) |
| `01-prepare.sh` | Kolla-Ansible, `/etc/kolla`, mots de passe générés, VG `cinder-volumes` sur `/dev/sda` |
| `02-deploy.sh` | bootstrap-servers, prechecks, pull, deploy, post-deploy (environ 20 minutes) |
| `03-bootstrap-ows.sh` | Réseau externe, image Ubuntu 24.04, gabarits, projet `ows`, quotas, identifiant d'application |

```bash
FIP_START=10.202.136.100 FIP_END=10.202.136.130 ./03-bootstrap-ows.sh
```

Déployé le 27/11/2026 : API `http://10.202.100.36:5000/v3`, Horizon `http://10.202.100.36`.
`openstack --os-cloud ows token issue` réussit avec l'utilisateur Linux `ows`.

La plage d'IP flottantes ne répondait pas à un balayage ARP le jour du déploiement ; elle n'est pas
réservée officiellement sur le réseau partagé. Non testés : redémarrage du serveur, accès à une VM.
