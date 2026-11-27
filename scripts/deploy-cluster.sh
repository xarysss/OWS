#!/usr/bin/env bash
# Orchestrateur, lancé depuis le poste d'administration (os-compute-6, /home/ows/OWS).
# Lit scripts/cluster.env et scripts/ssh_config générés par OpenTofu.
#
#   ./scripts/deploy-cluster.sh all          # prérequis + init + join + Cilium + ArgoCD
#   ./scripts/deploy-cluster.sh prereqs      # tous les nœuds
#   ./scripts/deploy-cluster.sh init         # premier control plane
#   ./scripts/deploy-cluster.sh join         # nœuds pas encore membres (phase 2 : 3+3)
#   ./scripts/deploy-cluster.sh kubeconfig   # récupère ~/.kube/ows.conf
#   ./scripts/deploy-cluster.sh cilium       # CNI (Helm, mêmes values qu'ArgoCD)
#   ./scripts/deploy-cluster.sh argocd       # ArgoCD + app-of-apps
#   ./scripts/deploy-cluster.sh status
#   ./scripts/deploy-cluster.sh upgrade 1.31 # voir docs/upgrade-1.31.md
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
source "$ROOT/scripts/versions.env"
[[ -f "$ROOT/scripts/cluster.env" ]] || die "scripts/cluster.env absent : lancer 'tofu apply' dans openstack/tofu"
source "$ROOT/scripts/cluster.env"

SSH="ssh -F $ROOT/scripts/ssh_config"
export KUBECONFIG="${KUBECONFIG_OWS:-$HOME/.kube/ows.conf}"
REMOTE_DIR=/opt/ows

CP_NAMES=($(pairs "$CONTROL_PLANES" | awk '{print $1}'))
WK_NAMES=($(pairs "$WORKERS" | awk '{print $1}'))
FIRST_CP="${CP_NAMES[0]}"

# Copie scripts/ et kubernetes/ sur le nœud (sans cluster.env ni secrets).
push() {
  tar -C "$ROOT" -czf - scripts/lib scripts/node scripts/versions.env kubernetes \
    | $SSH "$1" "sudo rm -rf $REMOTE_DIR && sudo mkdir -p $REMOTE_DIR && sudo tar -C $REMOTE_DIR -xzf -"
}
# Exécute un script de nœud en root avec des variables d'environnement.
run() { local node=$1 script=$2; shift 2
  $SSH "$node" "sudo env $* bash $REMOTE_DIR/scripts/node/$script"
}
member() { $SSH "$1" "sudo test -f /etc/kubernetes/kubelet.conf"; }

cmd_prereqs() {
  for n in "${CP_NAMES[@]}" "${WK_NAMES[@]}"; do
    log "== $n : prérequis"
    push "$n"
    run "$n" 00-prereqs.sh "CONTROL_PLANES='$CONTROL_PLANES'" "WORKERS='$WORKERS'" "API_VIP=$API_VIP"
    run "$n" 01-containerd.sh
    run "$n" 02-kube-packages.sh
  done
}

cmd_init() {
  log "== $FIRST_CP : kubeadm init"
  push "$FIRST_CP"
  run "$FIRST_CP" 10-init-first-cp.sh "API_VIP=$API_VIP" "API_FLOATING_IP=$API_FLOATING_IP"
  cmd_kubeconfig
}

cmd_join() {
  local token ca_hash cert_key
  token="$($SSH "$FIRST_CP" "sudo kubeadm token create --ttl 2h")"
  ca_hash="sha256:$($SSH "$FIRST_CP" "sudo openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt \
      | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'")"
  for n in "${CP_NAMES[@]:1}"; do
    member "$n" && { log "$n déjà membre"; continue; }
    # Nouvelle clé à chaque CP : elle expire après 2 h.
    cert_key="$($SSH "$FIRST_CP" "sudo kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1")"
    log "== $n : join control plane"
    push "$n"
    run "$n" 11-join.sh ROLE=control-plane "API_VIP=$API_VIP" "JOIN_TOKEN=$token" "CA_HASH=$ca_hash" "CERT_KEY=$cert_key"
  done
  for n in "${WK_NAMES[@]}"; do
    member "$n" && { log "$n déjà membre"; continue; }
    log "== $n : join worker"
    push "$n"
    run "$n" 11-join.sh ROLE=worker "API_VIP=$API_VIP" "JOIN_TOKEN=$token" "CA_HASH=$ca_hash"
  done
  $SSH "$FIRST_CP" "sudo kubeadm token delete $token" >/dev/null
  for n in "${WK_NAMES[@]}"; do
    kubectl label node "$n" node-role.kubernetes.io/worker= --overwrite >/dev/null 2>&1 || true
  done
}

cmd_kubeconfig() {
  mkdir -p "$(dirname "$KUBECONFIG")"
  $SSH "$FIRST_CP" "sudo cat /etc/kubernetes/admin.conf" > "$KUBECONFIG"
  chmod 600 "$KUBECONFIG"
  # Depuis l'extérieur du réseau OpenStack : VIP via son IP flottante.
  if [[ -n "${API_FLOATING_IP}" ]]; then
    sed -i "s#server: https://${API_VIP}:6443#server: https://${API_FLOATING_IP}:6443#" "$KUBECONFIG"
  fi
  log "kubeconfig : $KUBECONFIG (export KUBECONFIG=$KUBECONFIG)"
}

ensure_helm() {
  command -v helm >/dev/null && return
  log "Installation de Helm ${HELM_VERSION} dans ~/.local/bin"
  mkdir -p ~/.local/bin
  curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" | tar -xz -C /tmp linux-amd64/helm
  mv /tmp/linux-amd64/helm ~/.local/bin/helm
  export PATH="$HOME/.local/bin:$PATH"
}

cmd_cilium() {
  ensure_helm
  helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
  helm repo update cilium >/dev/null
  # Mêmes values que l'Application ArgoCD ; seules les ServiceMonitor sont coupées
  # (CRD Prometheus pas encore installées). ArgoCD les réactive ensuite.
  log "Cilium ${CILIUM_CHART_VERSION}"
  helm upgrade --install cilium cilium/cilium -n kube-system \
    --version "${CILIUM_CHART_VERSION}" \
    -f "$ROOT/gitops/values/cilium.yaml" \
    --set k8sServiceHost="${API_VIP}" \
    --set prometheus.serviceMonitor.enabled=false \
    --set operator.prometheus.serviceMonitor.enabled=false \
    --set hubble.metrics.serviceMonitor.enabled=false \
    --wait --timeout 10m
  kubectl -n kube-system rollout status ds/cilium --timeout=5m
  kubectl wait --for=condition=Ready nodes --all --timeout=5m
}

cmd_argocd() {
  ensure_helm
  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
  helm repo update argo >/dev/null
  log "ArgoCD ${ARGOCD_CHART_VERSION}"
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install argocd argo/argo-cd -n argocd \
    --version "${ARGOCD_CHART_VERSION}" \
    -f "$ROOT/gitops/values/argocd.yaml" --wait --timeout 10m
  log "App-of-apps"
  kubectl apply -f "$ROOT/gitops/root-app.yaml"
  log "Mot de passe admin initial (à changer puis supprimer le secret) :"
  echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

cmd_status() {
  kubectl get nodes -o wide
  kubectl get applications -n argocd 2>/dev/null || true
}

cmd_upgrade() {
  local target="${1:-$K8S_UPGRADE_MINOR}"
  warn "Upgrade vers ${target}. Prérequis : sauvegarde Velero + snapshot etcd (docs/upgrade-1.31.md)."
  read -rp "Continuer ? [oui/non] " ok; [[ "$ok" == "oui" ]] || exit 1
  local i=0
  for n in "${CP_NAMES[@]}" "${WK_NAMES[@]}"; do
    local mode=worker
    [[ " ${CP_NAMES[*]} " == *" $n "* ]] && mode=cp
    [[ $i -eq 0 ]] && mode=first-cp
    log "== $n (${mode})"
    push "$n"
    kubectl drain "$n" --ignore-daemonsets --delete-emptydir-data --timeout=10m
    run "$n" 90-upgrade-node.sh "MODE=$mode" "K8S_TARGET_MINOR=$target"
    kubectl uncordon "$n"
    kubectl wait --for=condition=Ready "node/$n" --timeout=5m
    # Laisser Ceph retrouver HEALTH_OK avant de passer au worker suivant.
    if [[ $mode == worker ]]; then
      kubectl -n rook-ceph wait --for=jsonpath='{.status.ceph.health}'=HEALTH_OK cephcluster/rook-ceph --timeout=15m || warn "Ceph pas HEALTH_OK"
    fi
    i=$((i+1))
  done
  kubectl get nodes
}

case "${1:-}" in
  prereqs)    cmd_prereqs ;;
  init)       cmd_init ;;
  join)       cmd_join ;;
  kubeconfig) cmd_kubeconfig ;;
  cilium)     cmd_cilium ;;
  argocd)     cmd_argocd ;;
  status)     cmd_status ;;
  upgrade)    shift; cmd_upgrade "$@" ;;
  all)        cmd_prereqs; cmd_init; cmd_join; cmd_cilium; cmd_argocd; cmd_status ;;
  *) sed -n '2,15p' "$0"; exit 1 ;;
esac
