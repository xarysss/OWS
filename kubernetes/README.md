# Kubernetes

Configuration du cluster kubeadm, hors applications gérées par ArgoCD.

- `kubeadm/` : `ClusterConfiguration` / `InitConfiguration` / `JoinConfiguration` (1.30, puis 1.31),
  endpoint d'API sur la VIP.
- `cilium/` : valeurs Helm de Cilium pour l'installation initiale (reprise ensuite par ArgoCD).

Aucun kubeconfig ni jeton de join n'est versionné.
