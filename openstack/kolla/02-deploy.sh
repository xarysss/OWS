#!/usr/bin/env bash
# Déploie OpenStack tout-en-un. Journal : /var/log/ows-kolla.log
set -euo pipefail
# shellcheck disable=SC1091
. /opt/kolla-venv/bin/activate
exec > >(tee -a /var/log/ows-kolla.log) 2>&1
for step in bootstrap-servers prechecks pull deploy post-deploy; do
  echo "=== $step $(date '+%F %T')"
  kolla-ansible "$step" -i /root/all-in-one
done
"$VIRTUAL_ENV/bin/pip" install -q python-openstackclient \
  -c https://releases.openstack.org/constraints/upper/2026.2
echo "=== OpenStack déployé"
