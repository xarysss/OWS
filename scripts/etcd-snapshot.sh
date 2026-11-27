#!/usr/bin/env bash
# Snapshot etcd avant une opération risquée (upgrade). Copié sur le poste d'admin.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
source "$ROOT/scripts/cluster.env"
SSH="ssh -F $ROOT/scripts/ssh_config"
CP="$(pairs "$CONTROL_PLANES" | awk 'NR==1{print $1}')"
TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$HOME/ows-backups"
$SSH "$CP" "sudo crictl exec \$(sudo crictl ps --name etcd -q) etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/lib/etcd/snap-$TS.db && sudo cat /var/lib/etcd/snap-$TS.db" > "$HOME/ows-backups/etcd-$TS.db"
$SSH "$CP" "sudo rm -f /var/lib/etcd/snap-$TS.db"
log "Snapshot : $HOME/ows-backups/etcd-$TS.db ($(du -h "$HOME/ows-backups/etcd-$TS.db" | cut -f1))"
