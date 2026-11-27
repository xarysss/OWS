# Kubernetes

Configuration du cluster kubeadm, hors applications gérées par ArgoCD.

- `kubeadm/` : `InitConfiguration` / `JoinConfiguration` (modèles `.tpl`, 1.30 puis 1.31),
  endpoint d'API sur la VIP, politique d'audit.
- `kube-vip/` : pod statique de la VIP de l'API.
- `vault/policies/` : politiques Vault (HCL).

Les valeurs Cilium sont dans `gitops/values/cilium.yaml` (mêmes valeurs pour l'installation
initiale et pour ArgoCD). Aucun kubeconfig ni jeton de join n'est versionné : les `.tpl`
sont remplis à l'exécution par `scripts/deploy-cluster.sh`.
