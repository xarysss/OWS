#!/usr/bin/env bash
# Mise à niveau d'un nœud vers K8S_TARGET_MINOR (voir docs/upgrade-1.31.md).
# Usage (root) : MODE=first-cp|cp|worker K8S_TARGET_MINOR=1.31 [K8S_TARGET_PATCH=1.31.x] ./90-upgrade-node.sh
# Le drain/uncordon est fait depuis le poste d'administration (deploy-cluster.sh upgrade).
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../lib/common.sh"
require_root
: "${MODE:?}" "${K8S_TARGET_MINOR:?}"
export DEBIAN_FRONTEND=noninteractive

log "Dépôt v${K8S_TARGET_MINOR}"
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_TARGET_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_TARGET_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq

if [[ -n "${K8S_TARGET_PATCH:-}" ]]; then
  PKG="$(apt-cache madison kubeadm | awk -v v="${K8S_TARGET_PATCH}" '$3 ~ "^"v"-" {print $3; exit}')"
else
  PKG="$(apt-cache madison kubeadm | awk '{print $3}' | sort -V | tail -1)"
fi
[[ -n "$PKG" ]] || die "version cible introuvable"
TARGET="v${PKG%%-*}"

log "1/3 kubeadm ${PKG}"
apt-mark unhold kubeadm >/dev/null
apt-get install -y -qq "kubeadm=${PKG}" >/dev/null
apt-mark hold kubeadm >/dev/null

log "2/3 kubeadm upgrade (${MODE})"
case "$MODE" in
  first-cp)
    kubeadm upgrade plan "$TARGET"
    kubeadm upgrade apply "$TARGET" -y ;;
  cp|worker)
    kubeadm upgrade node ;;
  *) die "MODE inconnu" ;;
esac

log "3/3 kubelet + kubectl ${PKG}"
apt-mark unhold kubelet kubectl >/dev/null
apt-get install -y -qq "kubelet=${PKG}" "kubectl=${PKG}" >/dev/null
apt-mark hold kubelet kubectl >/dev/null
# Image pause attendue par 1.31
sed -i -E 's#^([[:space:]]*sandbox(_image)?) = .*#\1 = "registry.k8s.io/pause:3.10"#' /etc/containerd/config.toml
systemctl restart containerd
systemctl daemon-reload
systemctl restart kubelet
log "Nœud $(hostname -s) en ${TARGET}"
