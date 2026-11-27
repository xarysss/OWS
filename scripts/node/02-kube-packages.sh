#!/usr/bin/env bash
# Installe kubeadm, kubelet, kubectl depuis pkgs.k8s.io et les bloque (apt-mark hold).
# Usage : K8S_MINOR=1.30 [K8S_PATCH=1.30.14] ./02-kube-packages.sh
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../lib/common.sh"
source "$DIR/../versions.env"
require_root
export DEBIAN_FRONTEND=noninteractive

log "Dépôt Kubernetes v${K8S_MINOR}"
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq

if [[ -n "${K8S_PATCH}" ]]; then
  PKG="$(apt-cache madison kubeadm | awk -v v="${K8S_PATCH}" '$3 ~ "^"v"-" {print $3; exit}')"
else
  PKG="$(apt-cache madison kubeadm | awk '{print $3}' | sort -V | tail -1)"
fi
[[ -n "$PKG" ]] || die "version introuvable dans le dépôt v${K8S_MINOR}"

log "Installation kubeadm/kubelet/kubectl ${PKG}"
apt-mark unhold kubeadm kubelet kubectl >/dev/null 2>&1 || true
apt-get install -y -qq "kubeadm=${PKG}" "kubelet=${PKG}" "kubectl=${PKG}" >/dev/null
apt-mark hold kubeadm kubelet kubectl >/dev/null
systemctl enable kubelet

# Le kubelet doit annoncer l'IP du réseau Kubernetes (pas une éventuelle autre interface).
NODE_IP="$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')"
echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" > /etc/default/kubelet
log "kubeadm $(kubeadm version -o short) installé, node-ip ${NODE_IP}"
