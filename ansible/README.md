# Ansible

Préparation des nœuds et installation de Kubernetes avec kubeadm.

- `inventory/` : inventaire. Le fichier réel (`hosts.yml`) est généré depuis les sorties
  OpenTofu et n'est pas versionné ; modèle : [`inventory/hosts.yml.example`](inventory/hosts.yml.example).
- `playbooks/` : prérequis (swap, modules, sysctl), containerd, kubeadm / kubelet / kubectl 1.30,
  init du premier control plane, join des control planes et des workers, upgrade 1.31.
- `roles/` : rôles réutilisables.
