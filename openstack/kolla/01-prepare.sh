#!/usr/bin/env bash
# Installe Kolla-Ansible, prépare /etc/kolla et le groupe LVM de Cinder. Rejouable.
set -euo pipefail
# Empêche deux exécutions simultanées.
exec 9>/run/lock/ows-kolla.lock
flock -n 9 || { echo "STOP : un autre script ows est déjà en cours"; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
venv=/opt/kolla-venv
disk=${CINDER_DISK:-/dev/sda}

dnf install -y -q git python3-devel libffi-devel gcc openssl-devel python3-libselinux lvm2
[ -x "$venv/bin/pip" ] || python3 -m venv --system-site-packages "$venv"
"$venv/bin/pip" install -q -U pip
[ -x "$venv/bin/kolla-ansible" ] || \
  "$venv/bin/pip" install -q 'git+https://opendev.org/openstack/kolla-ansible@stable/2026.2'
# shellcheck disable=SC1091
. "$venv/bin/activate"
kolla-ansible install-deps

install -d -m 750 /etc/kolla
install -m 644 "$here/globals.yml" /etc/kolla/globals.yml
if [ ! -f /etc/kolla/passwords.yml ]; then
  install -m 600 "$venv/share/kolla-ansible/etc_examples/kolla/passwords.yml" /etc/kolla/passwords.yml
  kolla-genpwd
fi
install -m 644 "$venv/share/kolla-ansible/ansible/inventory/all-in-one" /root/all-in-one

if ! vgs cinder-volumes >/dev/null 2>&1; then
  # Garde-fou : uniquement un disque entier, sans partition ni signature.
  [ "$(lsblk -nro NAME "$disk" | wc -l)" -eq 1 ] || { echo "STOP : $disk est partitionné"; exit 1; }
  [ -z "$(wipefs -n "$disk")" ] || { echo "STOP : $disk n'est pas vierge"; exit 1; }
  pvcreate "$disk"
  vgcreate cinder-volumes "$disk"
fi
echo "Préparation terminée."
