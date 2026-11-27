# GitOps (ArgoCD)

- `root-app.yaml` : application racine (app-of-apps), seule ressource appliquée à la main.
- `apps/` : un `AppProject` et une `Application` ArgoCD par composant (version du chart figée,
  ordre par sync-waves) : Cilium, MetalLB, Rook-Ceph, Vault, External Secrets,
  kube-prometheus-stack, Velero, ArgoCD lui-même.
- `values/` : `values.yaml` de chaque chart Helm.
- `manifests/` : configuration propre à OWS (pool MetalLB, `ExternalSecret`, tableau et
  alertes Grafana, `Schedule` Velero).

Règle : tout changement du cluster passe par un commit ici, ArgoCD synchronise.
Les secrets sont des `ExternalSecret` pointant vers Vault, jamais des `Secret` en clair.
