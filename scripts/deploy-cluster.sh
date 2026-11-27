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
#   ./scripts/deploy-cluster.sh validate     # contrôles du cluster (docs/validation-1-1.md)
#   ./scripts/deploy-cluster.sh tunnel       # API via tunnel SSH si l'IP flottante de la VIP ne répond pas
#   ./scripts/deploy-cluster.sh status
#   ./scripts/deploy-cluster.sh upgrade 1.31 # voir docs/upgrade-1.31.md
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
source "$ROOT/scripts/versions.env"
[[ -f "$ROOT/scripts/cluster.env" ]] || die "scripts/cluster.env absent : lancer 'tofu apply' dans openstack/tofu"
source "$ROOT/scripts/cluster.env"
[[ -f "$ROOT/scripts/ssh_config" ]] || die "scripts/ssh_config absent : lancer 'tofu apply' dans openstack/tofu"

SSH="ssh -F $ROOT/scripts/ssh_config"
export KUBECONFIG="${KUBECONFIG_OWS:-$HOME/.kube/ows.conf}"
export PATH="$HOME/.local/bin:$PATH"
REMOTE_DIR=/opt/ows
TUNNEL_PORT="${TUNNEL_PORT:-16443}"

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
  ensure_api
  for n in "${WK_NAMES[@]}"; do
    kubectl label node "$n" node-role.kubernetes.io/worker= --overwrite >/dev/null 2>&1 || true
  done
}

# L'API répond-elle à cette adresse ? (/livez est lisible sans authentification)
api_up() { curl -ksf --max-time 5 "https://$1/livez" >/dev/null; }

# Tunnel SSH poste -> VIP via le bastion (127.0.0.1 est dans les certSANs de l'API).
cmd_tunnel() {
  api_up "127.0.0.1:${TUNNEL_PORT}" && return
  log "Tunnel SSH 127.0.0.1:${TUNNEL_PORT} -> ${API_VIP}:6443 via ${FIRST_CP}"
  $SSH -f -N -o ExitOnForwardFailure=yes -L "127.0.0.1:${TUNNEL_PORT}:${API_VIP}:6443" "$FIRST_CP"
  sleep 1
  api_up "127.0.0.1:${TUNNEL_PORT}" || die "le tunnel ne répond pas"
}

cmd_kubeconfig() {
  mkdir -p "$(dirname "$KUBECONFIG")"
  ( umask 077; $SSH "$FIRST_CP" "sudo cat /etc/kubernetes/admin.conf" > "$KUBECONFIG" )
  # Depuis l'extérieur du réseau OpenStack : VIP via son IP flottante, sinon tunnel SSH
  # (certaines configurations Neutron ne NATent pas une IP flottante vers une VIP).
  local server
  if [[ -n "${API_FLOATING_IP:-}" ]] && api_up "${API_FLOATING_IP}:6443"; then
    server="${API_FLOATING_IP}:6443"
  else
    warn "VIP non joignable par IP flottante : passage par un tunnel SSH"
    cmd_tunnel
    server="127.0.0.1:${TUNNEL_PORT}"
  fi
  sed -i "s#server: https://.*:6443#server: https://${server}#" "$KUBECONFIG"
  log "kubeconfig : $KUBECONFIG (API ${server} ; export KUBECONFIG=$KUBECONFIG)"
}

# Rouvre le tunnel si le kubeconfig passe par lui (après un redémarrage du poste, etc.).
ensure_api() {
  [[ -f "$KUBECONFIG" ]] || cmd_kubeconfig
  grep -q "server: https://127.0.0.1:${TUNNEL_PORT}" "$KUBECONFIG" && cmd_tunnel
  ensure_kubectl
  kubectl version --request-timeout=10s >/dev/null || die "API Kubernetes injoignable (voir ${KUBECONFIG})"
}

ensure_kubectl() {
  command -v kubectl >/dev/null && return
  local v; v="$(curl -fsSL "https://dl.k8s.io/release/stable-${K8S_MINOR}.txt")"
  log "Installation de kubectl ${v} dans ~/.local/bin"
  mkdir -p ~/.local/bin
  curl -fsSLo ~/.local/bin/kubectl "https://dl.k8s.io/release/${v}/bin/linux/amd64/kubectl"
  chmod +x ~/.local/bin/kubectl
}

ensure_helm() {
  command -v helm >/dev/null && return
  log "Installation de Helm ${HELM_VERSION} dans ~/.local/bin"
  mkdir -p ~/.local/bin
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" | tar -xz -C "$tmp" linux-amd64/helm
  mv "$tmp/linux-amd64/helm" ~/.local/bin/helm
  rm -rf "$tmp"
}

cmd_cilium() {
  ensure_api
  ensure_helm
  helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
  helm repo update cilium >/dev/null
  # Mêmes values que l'Application ArgoCD, sauf :
  #  - ServiceMonitor coupées (CRD Prometheus pas encore installées) ;
  #  - Hubble UI en ClusterIP : MetalLB n'est pas encore là et « helm --wait » attendrait
  #    indéfiniment l'IP d'un Service LoadBalancer.
  # ArgoCD remet ensuite les values complètes.
  log "Cilium ${CILIUM_CHART_VERSION}"
  helm upgrade --install cilium cilium/cilium -n kube-system \
    --version "${CILIUM_CHART_VERSION}" \
    -f "$ROOT/gitops/values/cilium.yaml" \
    --set k8sServiceHost="${API_VIP}" \
    --set prometheus.serviceMonitor.enabled=false \
    --set operator.prometheus.serviceMonitor.enabled=false \
    --set hubble.metrics.serviceMonitor.enabled=false \
    --set hubble.ui.service.type=ClusterIP \
    --wait --timeout 10m
  kubectl -n kube-system rollout status ds/cilium --timeout=5m
  kubectl wait --for=condition=Ready nodes --all --timeout=5m
}

cmd_argocd() {
  ensure_api
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
  ensure_api
  kubectl get nodes -o wide
  kubectl get applications -n argocd 2>/dev/null || true
}

cmd_upgrade() {
  local target="${1:-$K8S_UPGRADE_MINOR}"
  ensure_api
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
  validate)   ensure_api; "$ROOT/scripts/validate-cluster.sh" ;;
  tunnel)     cmd_tunnel ;;
  upgrade)    shift; cmd_upgrade "$@" ;;
  all)        cmd_prereqs; cmd_init; cmd_join; cmd_cilium; cmd_argocd; cmd_status ;;
  *) sed -n '2,17p' "$0"; exit 1 ;;
esac
