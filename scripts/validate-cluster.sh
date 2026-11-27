#!/usr/bin/env bash
# Contrôles d'acceptation du cluster (phase 4 : 1+1, rejouable en 3+3).
# Lancé par « deploy-cluster.sh validate » (qui ouvre l'accès à l'API au besoin).
#
#   1. nœuds : tous Ready, nombre attendu (cluster.env), version 1.30
#   2. pods système : tous Running/Completed dans kube-system
#   3. Cilium : agent OK, kube-proxy absent (remplacé par Cilium)
#   4. VIP kube-vip : bail détenu par un control plane, API joignable via la VIP depuis un worker
#   5. charge de test : nginx sur un worker, client sur un control plane (trafic inter-nœuds
#      dans le tunnel VXLAN), résolution DNS du Service par CoreDNS
#
# Code de sortie 0 si tout passe. KEEP=1 conserve le namespace de test.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
source "$ROOT/scripts/versions.env"
source "$ROOT/scripts/cluster.env"
SSH="ssh -F $ROOT/scripts/ssh_config"
export KUBECONFIG="${KUBECONFIG_OWS:-${KUBECONFIG:-$HOME/.kube/ows.conf}}"
NS=ows-validation
FAILS=0

ok()  { printf '  \033[1;32mOK\033[0m    %s\n' "$*"; }
ko()  { printf '  \033[1;31mÉCHEC\033[0m %s\n' "$*"; FAILS=$((FAILS+1)); }
check() { local label=$1; shift; if "$@"; then ok "$label"; else ko "$label"; fi; }

CP_NAMES=($(pairs "$CONTROL_PLANES" | awk '{print $1}'))
WK_NAMES=($(pairs "$WORKERS" | awk '{print $1}'))
EXPECTED=$(( ${#CP_NAMES[@]} + ${#WK_NAMES[@]} ))

log "1. Nœuds (${#CP_NAMES[@]} CP + ${#WK_NAMES[@]} worker(s) attendus)"
kubectl wait --for=condition=Ready nodes --all --timeout=5m >/dev/null || true
kubectl get nodes -o wide
ready=$(kubectl get nodes --no-headers | awk '$2=="Ready"' | wc -l)
check "${ready}/${EXPECTED} nœuds Ready" test "$ready" -eq "$EXPECTED"
bad_ver=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' \
  | grep -vc "^v${K8S_MINOR}\." || true)
check "kubelet en v${K8S_MINOR}.x sur tous les nœuds" test "$bad_ver" -eq 0
for n in "${CP_NAMES[@]}"; do
  check "$n porte le rôle control-plane" \
    bash -c "kubectl get nodes -l node-role.kubernetes.io/control-plane -o name | grep -qx node/$n"
done

log "2. Pods système"
for _ in $(seq 1 30); do
  pending=$(kubectl get pods -n kube-system --no-headers | awk '$3!="Running" && $3!="Completed"' | wc -l)
  [[ $pending -eq 0 ]] && break; sleep 10
done
kubectl get pods -n kube-system -o wide
check "tous les pods kube-system Running/Completed" test "$pending" -eq 0
notready=$(kubectl get pods -n kube-system --no-headers | awk '$3=="Running" {split($2,a,"/"); if (a[1]!=a[2]) print}' | wc -l)
check "tous les conteneurs Ready" test "$notready" -eq 0
check "CoreDNS disponible" kubectl -n kube-system rollout status deploy/coredns --timeout=60s

log "3. Cilium"
check "agent Cilium OK" bash -c "kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status --brief | grep -q OK"
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep -E 'KubeProxyReplacement|Routing|Cluster health' || true
check "kube-proxy absent (remplacé par Cilium)" bash -c "! kubectl -n kube-system get ds kube-proxy >/dev/null 2>&1"

log "4. VIP de l'API ${API_VIP} (kube-vip)"
holder=$(kubectl -n kube-system get lease plndr-cp-lock -o jsonpath='{.spec.holderIdentity}' 2>/dev/null || true)
check "bail kube-vip détenu (${holder:-aucun})" bash -c "[[ ' ${CP_NAMES[*]} ' == *' ${holder} '* ]]"
for w in "${WK_NAMES[@]}"; do
  check "API joignable via la VIP depuis $w" $SSH "$w" "curl -ksf --max-time 5 https://${API_VIP}:6443/livez >/dev/null"
done

log "5. Charge de test (namespace ${NS})"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -n "$NS" -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports: [{ containerPort: 80 }]
          readinessProbe: { httpGet: { path: /, port: 80 } }
---
apiVersion: v1
kind: Service
metadata: { name: web }
spec:
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80 }]
YAML
check "déploiement web prêt" kubectl -n "$NS" rollout status deploy/web --timeout=3m
web_node=$(kubectl -n "$NS" get pod -l app=web -o jsonpath='{.items[0].spec.nodeName}')
check "pod web planifié sur un worker (${web_node})" bash -c "[[ ' ${WK_NAMES[*]} ' == *' ${web_node} '* ]]"

# Client épinglé sur le premier control plane : force un trafic inter-nœuds.
kubectl -n "$NS" delete pod client --ignore-not-found >/dev/null
kubectl -n "$NS" run client --image=busybox:1.36 --restart=Never \
  --overrides="{\"spec\":{\"nodeName\":\"${CP_NAMES[0]}\",\"tolerations\":[{\"operator\":\"Exists\"}]}}" \
  -- sleep 600 >/dev/null
check "pod client démarré sur ${CP_NAMES[0]}" kubectl -n "$NS" wait --for=condition=Ready pod/client --timeout=2m
web_ip=$(kubectl -n "$NS" get pod -l app=web -o jsonpath='{.items[0].status.podIP}')
check "pod -> pod inter-nœuds (${web_ip})" kubectl -n "$NS" exec client -- wget -qO- -T 5 "http://${web_ip}/"
check "DNS + Service (web.${NS}.svc.cluster.local)" \
  kubectl -n "$NS" exec client -- wget -qO- -T 5 "http://web.${NS}.svc.cluster.local/"
check "DNS externe (registry.k8s.io)" kubectl -n "$NS" exec client -- nslookup registry.k8s.io

if [[ "${KEEP:-0}" != 1 ]]; then
  kubectl delete namespace "$NS" --wait=false >/dev/null
fi

echo
if [[ $FAILS -eq 0 ]]; then
  log "Validation réussie : $(kubectl get nodes --no-headers | wc -l) nœuds, $(date '+%F %H:%M')"
else
  die "${FAILS} contrôle(s) en échec"
fi
