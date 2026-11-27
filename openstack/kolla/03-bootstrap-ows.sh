#!/usr/bin/env bash
# Réseau externe, image, gabarits, projet "ows", quotas et identifiant d'application. Rejouable.
# Usage : FIP_START=10.202.x.y FIP_END=10.202.x.z ./03-bootstrap-ows.sh
set -euo pipefail
exec 9>/run/lock/ows-kolla.lock
flock -n 9 || { echo "STOP : un autre script ows est déjà en cours"; exit 1; }
: "${FIP_START:?plage d'IP flottantes libres obligatoire (réseau partagé)}"
: "${FIP_END:?plage d'IP flottantes libres obligatoire (réseau partagé)}"
# shellcheck disable=SC1091
. /opt/kolla-venv/bin/activate
export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
os() { openstack --os-cloud kolla-admin "$@"; }
has() { os "$@" >/dev/null 2>&1; }

has network show public || os network create --external --share \
  --provider-network-type flat --provider-physical-network physnet1 public >/dev/null
has subnet show public-v4 || os subnet create --network public --subnet-range 10.202.0.0/16 \
  --gateway 10.202.255.254 --no-dhcp --allocation-pool "start=$FIP_START,end=$FIP_END" \
  public-v4 >/dev/null

if ! has image show ubuntu-24.04; then
  base=https://cloud-images.ubuntu.com/noble/current
  file=noble-server-cloudimg-amd64.img
  install -d /home/ows-images && cd /home/ows-images
  curl -fsSL -o "$file" "$base/$file"
  curl -fsSL "$base/SHA256SUMS" | grep " \*\?$file\$" | sha256sum -c -
  os image create --public --disk-format qcow2 --container-format bare --file "$file" \
    ubuntu-24.04 >/dev/null
fi

has flavor show ows.cp     || os flavor create --vcpus 3 --ram 8192  --disk 40 ows.cp >/dev/null
has flavor show ows.worker || os flavor create --vcpus 4 --ram 14336 --disk 40 ows.worker >/dev/null

has project show ows || os project create --description "SAE Cloud OWS" ows >/dev/null
secret=/root/ows-user.password
[ -s "$secret" ] || (umask 077; openssl rand -base64 30 > "$secret")
has user show ows || os user create --project ows --password "$(cat "$secret")" ows >/dev/null
os role add --project ows --user ows member
os quota set --instances 10 --cores 24 --ram 81920 --volumes 10 --gigabytes 600 \
  --floating-ips 8 ows

# Le fournisseur OpenTofu cherche Cinder sous le type "volumev3".
has service show cinderv3 || os service create --name cinderv3 volumev3 >/dev/null
for iface in public internal; do
  [ -n "$(os endpoint list --service cinderv3 --interface "$iface" -f value -c ID)" ] ||     os endpoint create --region RegionOne cinderv3 "$iface" http://10.202.100.36:8776/v3 >/dev/null
done

# Identifiant d'application pour l'utilisateur Linux "ows" (OpenTofu, client openstack).
target=/home/ows/.config/openstack/clouds.yaml
if [ ! -s "$target" ]; then
  url=http://10.202.100.36:5000/v3
  cred=$(env -u OS_CLOUD OS_AUTH_URL=$url OS_USERNAME=ows OS_PASSWORD="$(cat "$secret")" \
    OS_PROJECT_NAME=ows OS_USER_DOMAIN_NAME=Default OS_PROJECT_DOMAIN_NAME=Default \
    openstack application credential create "ows-$(date +%Y%m%d%H%M%S)" -f json)
  install -d -o ows -g ows -m 700 /home/ows/.config /home/ows/.config/openstack
  (umask 077; CRED="$cred" URL="$url" python3 - > "$target" <<'PY'
import json, os
c = {k.lower(): v for k, v in json.loads(os.environ["CRED"]).items()}
print(f"""clouds:
  ows:
    auth_type: v3applicationcredential
    auth:
      auth_url: {os.environ['URL']}
      application_credential_id: "{c['id']}"
      application_credential_secret: "{c['secret']}"
    region_name: RegionOne
    interface: public
    identity_api_version: 3""")
PY
  )
  chown ows:ows "$target"
fi
echo "Projet ows prêt."
