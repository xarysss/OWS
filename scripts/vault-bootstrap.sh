#!/usr/bin/env bash
# Initialise Vault (une seule fois), le descelle et le configure pour External Secrets.
# Les clés de descellement et le jeton root ne sont JAMAIS écrits dans le dépôt :
# ils vont dans ~/ows-secrets/ (chmod 700) sur le poste d'administration, puis
# dans le gestionnaire de mots de passe de l'équipe. Voir docs/secrets-vault.md.
#
#   ./scripts/vault-bootstrap.sh init      # init + descellement des 3 pods + raft join
#   ./scripts/vault-bootstrap.sh unseal    # après un redémarrage de pod
#   ./scripts/vault-bootstrap.sh configure # kv-v2, auth kubernetes, politiques, rôles
#   ./scripts/vault-bootstrap.sh seed      # saisie interactive des secrets applicatifs
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
export KUBECONFIG="${KUBECONFIG_OWS:-$HOME/.kube/ows.conf}"
NS=vault
SECRETS_DIR="$HOME/ows-secrets"
INIT_FILE="$SECRETS_DIR/vault-init.json"
PODS=(vault-0 vault-1 vault-2)

vexec() { local pod=$1; shift; kubectl -n $NS exec "$pod" -- "$@"; }
root_token() { jq -r .root_token "$INIT_FILE"; }
vroot() { kubectl -n $NS exec -i vault-0 -- env VAULT_TOKEN="$(root_token)" "$@"; }

unseal_pod() {
  local pod=$1
  for i in 0 1 2; do
    vexec "$pod" vault operator unseal "$(jq -r ".unseal_keys_b64[$i]" "$INIT_FILE")" >/dev/null
  done
  log "$pod descellé"
}

cmd_init() {
  mkdir -p "$SECRETS_DIR" && chmod 700 "$SECRETS_DIR"
  [[ -f "$INIT_FILE" ]] && die "$INIT_FILE existe déjà : Vault est déjà initialisé"
  kubectl -n $NS wait --for=jsonpath='{.status.phase}'=Running pod/vault-0 --timeout=10m
  umask 077
  vexec vault-0 vault operator init -key-shares=5 -key-threshold=3 -format=json > "$INIT_FILE"
  log "Clés écrites dans $INIT_FILE : à copier dans le coffre de l'équipe puis à retirer du disque"
  unseal_pod vault-0
  for p in "${PODS[@]:1}"; do
    vexec "$p" vault operator raft join http://vault-0.vault-internal:8200 >/dev/null || true
    unseal_pod "$p"
  done
  vroot vault operator raft list-peers
}

cmd_unseal() {
  [[ -f "$INIT_FILE" ]] || die "Poser temporairement le fichier d'init dans $INIT_FILE"
  for p in "${PODS[@]}"; do
    if vexec "$p" vault status -format=json 2>/dev/null | jq -e '.sealed' >/dev/null; then unseal_pod "$p"; fi
  done
}

cmd_configure() {
  log "Moteur KV v2 sur secret/"
  vroot vault secrets enable -path=secret -version=2 kv 2>/dev/null || log "déjà activé"
  log "Auth Kubernetes"
  vroot vault auth enable kubernetes 2>/dev/null || log "déjà activée"
  vroot vault write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc:443"
  log "Politiques"
  for f in "$ROOT"/kubernetes/vault/policies/*.hcl; do
    name="$(basename "$f" .hcl)"
    kubectl -n $NS exec -i vault-0 -- env VAULT_TOKEN="$(root_token)" vault policy write "$name" - < "$f"
  done
  log "Rôle external-secrets (lecture seule sur secret/data/ows/*)"
  vroot vault write auth/kubernetes/role/external-secrets \
    bound_service_account_names=external-secrets \
    bound_service_account_namespaces=external-secrets \
    policies=external-secrets-read ttl=1h
  log "Audit Vault sur stdout (collecté par les logs du pod)"
  vroot vault audit enable file file_path=stdout 2>/dev/null || true
}

ask() { local v; read -rsp "$1 : " v; echo >&2; printf '%s' "$v"; }

cmd_seed() {
  log "Saisie des secrets (rien n'est affiché ni enregistré localement)"
  vroot vault kv put secret/ows/grafana admin-user=admin admin-password="$(ask 'Mot de passe admin Grafana')"
  vroot vault kv put secret/ows/velero \
    aws_access_key_id="$(ask 'Clé d accès S3 Velero')" \
    aws_secret_access_key="$(ask 'Clé secrète S3 Velero')"
  vroot vault kv put secret/ows/alertmanager webhook-url="$(ask 'URL webhook alertes (Discord/Teams, vide sinon)')"
  log "Secrets écrits ; External Secrets les synchronise sous 1 minute"
}

case "${1:-}" in
  init) cmd_init ;; unseal) cmd_unseal ;; configure) cmd_configure ;; seed) cmd_seed ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
