#!/usr/bin/env bash
# Pose le pod statique kube-vip qui porte la VIP de l'API (mode ARP + élection de leader).
# Usage : API_VIP=10.20.0.10 FIRST_CP=true|false ./03-kube-vip.sh
#  - premier CP (avant kubeadm init) : FIRST_CP=true -> utilise super-admin.conf
#    (depuis 1.29, admin.conf n'a pas encore les droits pendant l'init).
#  - autres CP (après kubeadm join)  : FIRST_CP=false -> admin.conf
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../lib/common.sh"
source "$DIR/../versions.env"
require_root
: "${API_VIP:?API_VIP manquant}"
FIRST_CP="${FIRST_CP:-false}"

IFACE="${KUBE_VIP_INTERFACE}"
ip link show "$IFACE" >/dev/null 2>&1 || IFACE="$(ip -4 route show default | awk '{print $5; exit}')"

KCONF=/etc/kubernetes/admin.conf
[[ "$FIRST_CP" == "true" ]] && KCONF=/etc/kubernetes/super-admin.conf

mkdir -p /etc/kubernetes/manifests
export API_VIP IFACE KCONF KUBE_VIP_VERSION
envsubst '${API_VIP} ${IFACE} ${KCONF} ${KUBE_VIP_VERSION}' \
  < "$DIR/../../kubernetes/kube-vip/kube-vip.yaml.tpl" \
  > /etc/kubernetes/manifests/kube-vip.yaml
log "kube-vip ${KUBE_VIP_VERSION} : VIP ${API_VIP} sur ${IFACE} (kubeconfig ${KCONF})"
