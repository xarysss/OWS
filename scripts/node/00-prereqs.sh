#!/usr/bin/env bash
# Prérequis système d'un nœud Kubernetes (Ubuntu 24.04). Idempotent.
# Usage (root) : CONTROL_PLANES="..." WORKERS="..." API_VIP=... ./00-prereqs.sh
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../lib/common.sh"
require_root

log "Swap désactivé"
swapoff -a
sed -i '/\sswap\s/s/^/#/' /etc/fstab

log "Modules noyau"
cat > /etc/modules-load.d/k8s.conf <<CONF
overlay
br_netfilter
CONF
modprobe overlay
modprobe br_netfilter

log "sysctl réseau"
cat > /etc/sysctl.d/99-kubernetes.conf <<CONF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
# Rook-Ceph / Prometheus ouvrent beaucoup de fichiers
fs.inotify.max_user_instances       = 8192
fs.inotify.max_user_watches         = 524288
CONF
sysctl --system >/dev/null

log "/etc/hosts"
{
  echo "127.0.0.1 localhost"
  echo "${API_VIP} k8s-api.ows.local k8s-api"
  pairs "${CONTROL_PLANES} ${WORKERS}" | while read -r n ip; do echo "$ip $n.ows.local $n"; done
} > /etc/hosts

log "Paquets de base"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl gpg ca-certificates apt-transport-https jq chrony lvm2 nfs-common gettext-base >/dev/null
systemctl enable --now chrony

# ufw est inactif par défaut sur l'image cloud ; le filtrage est fait par les
# groupes de sécurité OpenStack.
systemctl disable --now ufw 2>/dev/null || true
log "Prérequis OK"
