#!/usr/bin/env bash
# Installe et configure containerd (cgroup systemd). Idempotent.
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../lib/common.sh"
source "$DIR/../versions.env"
require_root

export DEBIAN_FRONTEND=noninteractive
log "Installation de containerd (dépôt Ubuntu)"
apt-get install -y -qq containerd >/dev/null

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# kubelet et containerd doivent utiliser le même pilote cgroup (systemd).
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
# Image pause attendue par kubeadm (3.9 en 1.30, 3.10 en 1.31).
# containerd 1.7 : sandbox_image = "..." ; containerd 2.x : sandbox = '...'
sed -i -E "s#^([[:space:]]*sandbox(_image)?) = .*#\1 = \"${PAUSE_IMAGE}\"#" /etc/containerd/config.toml
grep -q "${PAUSE_IMAGE}" /etc/containerd/config.toml || die "image pause non appliquée"

cat > /etc/crictl.yaml <<CONF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
CONF

systemctl enable containerd
systemctl restart containerd
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml || die "SystemdCgroup non appliqué"
log "containerd $(containerd --version | awk '{print $3}') prêt"
