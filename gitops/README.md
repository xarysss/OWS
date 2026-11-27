# GitOps (ArgoCD)

- `bootstrap/` : installation d'ArgoCD (Helm) et application racine (app-of-apps).
- `apps/` : une `Application` ArgoCD par composant, avec ses valeurs Helm, par exemple
  `cilium/`, `metallb/`, `ingress/`, `rook-ceph/`, `vault/`, `external-secrets/`,
  `monitoring/`, `velero/`, `logging/`, `demo/`.

Règle : tout changement du cluster passe par un commit ici, ArgoCD synchronise.
Les secrets sont des `ExternalSecret` pointant vers Vault, jamais des `Secret` en clair.
