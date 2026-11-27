# Choix Helm ou Operator pour chaque composant

Le bon de commande demande d'installer chaque composant par Helm ou par un Operator et de justifier ce choix. Règle suivie : **Helm pour livrer, Operator quand le composant gère des données ou un cycle de vie complexe**. Dans les deux cas, ArgoCD applique le chart avec un `values.yaml` versionné, rien n'est appliqué à la main hors `root-app.yaml`.

| Composant | Méthode | Justification |
|---|---|---|
| Cilium | Helm (chart officiel) | Chart maintenu par le projet, seule méthode documentée pour kube-proxy replacement ; installé une fois en CLI (le cluster n'a pas de réseau sans lui) puis repris par ArgoCD avec les mêmes values |
| MetalLB | Helm + CRD | Chart officiel ; la configuration (IPAddressPool, L2Advertisement) est séparée en CRD pour pouvoir changer la plage sans toucher au chart |
| Rook-Ceph | **Operator** (installé par Helm) | Ceph a un cycle de vie complexe (OSD, mons, mises à jour en roulement, reprise après panne) ; l'opérateur Rook le gère, le chart `rook-ceph-cluster` décrit l'état voulu (CephCluster) |
| ArgoCD | Helm | Chart communautaire officiel ; ArgoCD se gère lui-même ensuite (self-management) |
| Vault | Helm (chart HashiCorp) | Chart officiel avec HA Raft ; un opérateur (Bank-Vaults) ajouterait l'auto-unseal mais une dépendance de plus |
| External Secrets | **Operator** (installé par Helm) | Réconcilie en continu les Secrets avec Vault : rotation sans redéploiement |
| Prometheus / Grafana | **Operator** (kube-prometheus-stack) | Prometheus Operator : chaque composant déclare sa ServiceMonitor, Prometheus la découvre seul ; tableaux Grafana en ConfigMap |
| Velero | Helm | Chart officiel ; planifications en CRD `Schedule` versionnées |
| kube-vip | Pod statique (YAML) | Doit exister avant l'API : ni Helm ni ArgoCD ne peuvent le livrer |

Versions des charts : figées dans `gitops/apps/*.yaml` (`targetRevision`). Une mise à jour = un commit qui change ce numéro, visible et réversible dans l'historique Git.
