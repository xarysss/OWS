#!/usr/bin/env bash
# Vérifie que chaque VM est joignable en SSH et que cloud-init a fini.
# Usage, depuis la racine du dépôt après « tofu apply » :  ./openstack/tofu/check-ssh.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOSTS="$ROOT/scripts/hosts.txt"
[[ -f "$HOSTS" ]] || { echo "scripts/hosts.txt absent : lancer 'tofu apply'" >&2; exit 1; }
SSH="ssh -n -F $ROOT/scripts/ssh_config -o BatchMode=yes -o ConnectTimeout=10"
TRIES="${TRIES:-30}"   # 30 x 10 s : le temps du premier démarrage

ko=0
while read -r name ip role; do
  for ((i = 1; i <= TRIES; i++)); do
    $SSH "$name" true 2>/dev/null && break
    sleep 10
  done
  if ! out="$($SSH "$name" 'cloud-init status --wait >/dev/null; echo "$(hostname) $(lsb_release -ds) swap=$(swapon --show | wc -l) vdb=$(lsblk -dno SIZE /dev/vdb 2>/dev/null || echo -)"' 2>&1)"; then
    echo "KO  $name ($ip, $role) : $out"; ko=1; continue
  fi
  echo "OK  $name ($ip, $role) : $out"
done < "$HOSTS"
exit $ko
