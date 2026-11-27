#!/usr/bin/env bash
# kubeadm init sur le premier control plane. controlPlaneEndpoint = VIP dès la
# phase 1 : c'est ce qui permet d'ajouter 2 CP plus tard sans reconstruire.
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../lib/common.sh"
source "$DIR/../versions.env"
require_root
: "${API_VIP:?}"

if [[ -f /etc/kubernetes/admin.conf ]]; then
  log "Cluster déjà initialisé, rien à faire"; exit 0
fi

export API_VIP POD_CIDR SERVICE_CIDR CLUSTER_NAME
export K8S_VERSION="v$(kubeadm version -o short | sed 's/^v//')"
export NODE_NAME="$(hostname -s)"
export NODE_IP="$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')"
envsubst < "$DIR/../../kubernetes/kubeadm/kubeadm-init.yaml.tpl" > /root/kubeadm-init.yaml
# IP flottante de la VIP dans le certificat de l'API (kubectl depuis os-compute-6).
if [[ -n "${API_FLOATING_IP:-}" ]]; then
  sed -i "s#^    - 127.0.0.1#    - 127.0.0.1\n    - ${API_FLOATING_IP}#" /root/kubeadm-init.yaml
fi

mkdir -p /etc/kubernetes
install -m 0600 "$DIR/../../kubernetes/kubeadm/audit-policy.yaml" /etc/kubernetes/audit-policy.yaml
FIRST_CP=true API_VIP="$API_VIP" "$DIR/03-kube-vip.sh"

log "kubeadm init (${K8S_VERSION})"
kubeadm init --config /root/kubeadm-init.yaml --upload-certs | tee /root/kubeadm-init.log

# Retour à admin.conf pour kube-vip (super-admin ne doit pas rester utilisé).
sed -i 's#/etc/kubernetes/super-admin.conf#/etc/kubernetes/admin.conf#' /etc/kubernetes/manifests/kube-vip.yaml

mkdir -p /home/ubuntu/.kube /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube
log "Control plane initialisé. Le nœud reste NotReady tant que Cilium n'est pas installé."
