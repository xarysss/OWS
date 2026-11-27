#!/usr/bin/env bash
# Phase 1 : installe les outils d'administration OWS sur os-compute-6.
# À lancer en root : crée l'utilisateur ows puis installe, dans /home/ows,
# le client OpenStack, Ansible, kubectl et Helm (OpenTofu en paquet système).
# Idempotent : peut être relancé sans risque.
set -euo pipefail

OWS_USER="${OWS_USER:-ows}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=versions.env
source "${SCRIPT_DIR}/versions.env"
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.30.14}"

[[ $EUID -eq 0 ]] || { echo "À lancer en root" >&2; exit 1; }

# 1. Utilisateur d'administration (connexion par clé uniquement, pas de mot de passe)
id "$OWS_USER" &>/dev/null || useradd -m -s /bin/bash -c "Administration OWS" "$OWS_USER"
HOME_DIR="$(getent passwd "$OWS_USER" | cut -d: -f6)"
install -d -m 700 -o "$OWS_USER" -g "$OWS_USER" "$HOME_DIR/.ssh" "$HOME_DIR/.config" \
  "$HOME_DIR/.config/openstack" "$HOME_DIR/.local" "$HOME_DIR/.local/bin"

# 2. Paquets système et OpenTofu (dépôt RPM officiel)
dnf install -y -q git jq python3-pip tar unzip
if ! command -v tofu &>/dev/null; then
  curl -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/install-opentofu.sh
  sh /tmp/install-opentofu.sh --install-method rpm
  rm -f /tmp/install-opentofu.sh
fi

# 3. Outils utilisateur (venv Python + binaires dans ~/.local/bin)
su - "$OWS_USER" -s /bin/bash <<EOF
set -euo pipefail
[[ -d ~/.venvs/ows ]] || python3 -m venv ~/.venvs/ows
~/.venvs/ows/bin/pip install -q --upgrade pip python-openstackclient ansible-core
for b in openstack ansible ansible-playbook ansible-galaxy ansible-inventory; do
  ln -sf ~/.venvs/ows/bin/\$b ~/.local/bin/\$b
done
curl -fsSLo ~/.local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x ~/.local/bin/kubectl
curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" | tar -xzO linux-amd64/helm > ~/.local/bin/helm
chmod +x ~/.local/bin/helm
[[ -f ~/.ssh/ows_ed25519 ]] || ssh-keygen -q -t ed25519 -N "" -C "ows@\$(hostname -s)" -f ~/.ssh/ows_ed25519
grep -q '^export OS_CLOUD=' ~/.bashrc || printf '\n# OWS\nexport OS_CLOUD=ows\nexport KUBECONFIG=\$HOME/.kube/ows.conf\n' >> ~/.bashrc
[[ -d ~/OWS ]] || git clone -q https://github.com/xarysss/OWS.git ~/OWS
EOF

# 4. Versions installées
su - "$OWS_USER" -c 'openstack --version; ansible --version | head -1; kubectl version --client | head -1; helm version --short; tofu version | head -1'
echo "Reste à placer clouds.yaml dans ${HOME_DIR}/.config/openstack/ (chmod 600), puis : openstack token issue"
