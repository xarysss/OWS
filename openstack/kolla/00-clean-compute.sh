#!/usr/bin/env bash
# Retire l'ancien rôle "compute du cloud partagé", après sauvegarde. Ne touche ni au système
# ni à la carte de management. Usage : CONFIRM=sortir-du-cloud ./00-clean-compute.sh
set -euo pipefail
[ "${CONFIRM:-}" = "sortir-du-cloud" ] || { echo "Relancer avec CONFIRM=sortir-du-cloud"; exit 1; }
[ -f /etc/kolla/nova-compute/nova.conf ] || { echo "Aucun ancien compute détecté, rien à faire."; exit 0; }
vms=$(podman exec nova_libvirt virsh -r list --all --name | grep -c . || true)
[ "$vms" = 0 ] || { echo "STOP : $vms VM présentes sur ce nœud."; exit 1; }

backup=/home/ows-backup/ancien-compute-$(date +%Y%m%d-%H%M%S)
install -d -m 700 "$backup"
mapfile -t containers < <(podman ps -a --format '{{.Names}}')
shopt -s nullglob
units=(/etc/systemd/system/kolla-*-container.service)
podman inspect "${containers[@]}" > "$backup/conteneurs.json"
[ "${#units[@]}" -eq 0 ] || cp -a "${units[@]}" "$backup/"
cp -a /etc/hosts "$backup/hosts"
podman exec openvswitch_vswitchd ovs-vsctl show > "$backup/ovs.txt"

# Retire les ponts OVS tant qu'OVS tourne (nettoie aussi le datapath noyau).
for u in "${units[@]}"; do
  case "$u" in *ovn_controller*|*neutron*|*nova*) systemctl stop "$(basename "$u")" ;; esac
done
# tar renvoie 1 si un journal change pendant la lecture : toléré, puis archive vérifiée.
tar -C / -czf "$backup/etc-kolla-et-volumes.tar.gz" etc/kolla var/lib/containers/storage/volumes \
  || [ $? -eq 1 ]
tar -tzf "$backup/etc-kolla-et-volumes.tar.gz" >/dev/null
for br in br-int br-ex; do podman exec openvswitch_vswitchd ovs-vsctl --if-exists del-br "$br"; done

for u in "${units[@]}"; do systemctl disable --now "$(basename "$u")"; rm -f "$u"; done
systemctl daemon-reload
podman rm -f "${containers[@]}" >/dev/null 2>&1 || true
podman volume rm -a -f >/dev/null
rm -rf /etc/kolla
sed -i '/# BEGIN ANSIBLE GENERATED HOSTS/,/# END ANSIBLE GENERATED HOSTS/d' /etc/hosts
echo "Ancien rôle compute retiré. Sauvegarde : $backup"
