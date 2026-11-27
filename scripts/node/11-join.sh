#!/usr/bin/env bash
# Joint un nœud au cluster via un fichier JoinConfiguration (pas de commande à rallonge).
# Usage : ROLE=control-plane|worker API_VIP=... JOIN_TOKEN=... CA_HASH=sha256:... [CERT_KEY=...] ./11-join.sh
# Le jeton (24 h) et la clé de certificats (2 h) sont générés par deploy-cluster.sh
# juste avant le join et ne sont jamais écrits dans le dépôt.
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../lib/common.sh"
source "$DIR/../versions.env"
require_root
: "${ROLE:?}" "${API_VIP:?}" "${JOIN_TOKEN:?}" "${CA_HASH:?}"

if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  log "Nœud déjà membre du cluster"; exit 0
fi

export API_VIP JOIN_TOKEN CA_HASH CERT_KEY="${CERT_KEY:-}"
export NODE_NAME="$(hostname -s)"
export NODE_IP="$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')"

TPL="$DIR/../../kubernetes/kubeadm/kubeadm-join-worker.yaml.tpl"
[[ "$ROLE" == "control-plane" ]] && TPL="$DIR/../../kubernetes/kubeadm/kubeadm-join-control-plane.yaml.tpl"
umask 077
envsubst < "$TPL" > /root/kubeadm-join.yaml

if [[ "$ROLE" == "control-plane" ]]; then
  mkdir -p /etc/kubernetes
  install -m 0600 "$DIR/../../kubernetes/kubeadm/audit-policy.yaml" /etc/kubernetes/audit-policy.yaml
fi

log "kubeadm join (${ROLE})"
kubeadm join --config /root/kubeadm-join.yaml
shred -u /root/kubeadm-join.yaml   # contient le jeton

if [[ "$ROLE" == "control-plane" ]]; then
  FIRST_CP=false API_VIP="$API_VIP" "$DIR/03-kube-vip.sh"
  mkdir -p /root/.kube /home/ubuntu/.kube
  cp /etc/kubernetes/admin.conf /root/.kube/config
  cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
  chown -R ubuntu:ubuntu /home/ubuntu/.kube
fi
log "Join terminé"
