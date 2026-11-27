# Gestion des secrets : Vault et External Secrets

## Principe

Aucun secret n'est écrit dans le dépôt, ni en clair ni chiffré. Les fichiers YAML ne contiennent que des **références** (nom d'un Secret Kubernetes, chemin dans Vault).

```
 Administrateur ──(vault kv put)──▶ Vault (3 pods, Raft sur Ceph)
                                         ▲
                                         │ auth Kubernetes (jeton du ServiceAccount)
                                         │ politique external-secrets-read (lecture seule secret/ows/*)
                          External Secrets Operator
                                         │ crée / met à jour toutes les heures
                                         ▼
                     Secret Kubernetes (grafana-admin, velero-credentials, alertmanager-ows)
                                         │
                                         ▼
                              Pods (Grafana, Velero, Alertmanager)
```

| Secret | Chemin Vault | Consommé par | Manifest |
|---|---|---|---|
| Admin Grafana | `secret/ows/grafana` (`admin-user`, `admin-password`) | Grafana (`admin.existingSecret`) | `gitops/manifests/external-secrets-config/grafana.yaml` |
| Clés S3 Velero | `secret/ows/velero` | Velero (`credentials.existingSecret`) | `.../velero.yaml` |
| Webhook d'alertes | `secret/ows/alertmanager` | Alertmanager (`configSecret`) | `.../alertmanager.yaml` |

Secrets restés hors Vault, et pourquoi :

| Secret | Où | Raison |
|---|---|---|
| `clouds.yaml` (identifiant d'application OpenStack) | `~/.config/openstack/` sur os-compute-6, `chmod 600` | Nécessaire avant que le cluster (et donc Vault) existe |
| Clés de descellement + jeton root Vault | Gestionnaire de mots de passe de l'équipe (2 personnes) | Vault ne peut pas garder ses propres clés |
| État OpenTofu | `openstack/tofu/terraform.tfstate`, ignoré par Git | Contient des identifiants de ressources ; à déplacer vers un backend S3 chiffré en production |
| PKI Kubernetes (`/etc/kubernetes/pki`) | Sur les control planes, `0600` root | Gérée par kubeadm |
| Jeton de join et clé de certificats | Générés à la volée par `deploy-cluster.sh`, TTL 2 h, fichier détruit (`shred`) après le join | Jamais stockés |

## Configuration des control planes

- Fichiers sensibles des CP : `/etc/kubernetes/pki/*` (CA du cluster, etcd, front-proxy), `admin.conf`, `super-admin.conf`. Seul root y accède.
- `super-admin.conf` (depuis 1.29) contourne RBAC : il ne sert qu'à kube-vip pendant le `kubeadm init`, puis le manifeste repasse sur `admin.conf` (`scripts/node/10-init-first-cp.sh`).
- Les certificats sont partagés entre CP via `kubeadm init phase upload-certs` : chiffrés dans le Secret `kubeadm-certs` avec une clé valable 2 h, régénérée à chaque join.
- L'audit de l'API est actif (`kubernetes/kubeadm/audit-policy.yaml`) : les Secrets et ConfigMaps sont journalisés au niveau `Metadata` seulement, jamais leur contenu.
- Les Secrets Kubernetes sont stockés dans etcd. Amélioration prévue : chiffrement au repos (`EncryptionConfiguration` avec `aescbc` ou KMS Vault).

## Installation et amorçage de Vault

Vault est déployé par ArgoCD (`gitops/apps/vault.yaml`, values `gitops/values/vault.yaml`) : 3 réplicas, stockage Raft intégré sur des PVC `ceph-block`, anti-affinité (un pod par nœud), UI sur `10.20.0.203:8200`.

```bash
./scripts/vault-bootstrap.sh init
```

- `vault operator init -key-shares=5 -key-threshold=3` : 5 clés, 3 suffisent pour desceller.
- Le résultat va dans `~/ows-secrets/vault-init.json` (`chmod 600`). **Le copier immédiatement dans le gestionnaire de mots de passe, puis supprimer le fichier** : `shred -u ~/ows-secrets/vault-init.json`.
- `vault-1` et `vault-2` rejoignent le cluster Raft puis sont descellés.

```bash
./scripts/vault-bootstrap.sh configure
```

- Active le moteur `kv` v2 sur `secret/`.
- Active l'auth `kubernetes` : External Secrets s'authentifie avec le jeton de son ServiceAccount, aucun identifiant à stocker.
- Écrit les politiques de `kubernetes/vault/policies/` et le rôle `external-secrets` (ServiceAccount `external-secrets/external-secrets`, TTL 1 h).
- Active l'audit Vault.

```bash
./scripts/vault-bootstrap.sh seed
```

Saisie masquée des valeurs ; rien n'est écrit sur le disque ni dans l'historique du shell.

Après l'amorçage, créer un jeton nominatif par administrateur et révoquer le jeton root :

```bash
kubectl -n vault exec -it vault-0 -- vault token create -policy=ows-admin -display-name=titouan -ttl=720h
kubectl -n vault exec -it vault-0 -- vault token revoke <root_token>
```

## Opérations courantes

Ajouter ou changer un secret :

```bash
kubectl -n vault exec -it vault-0 -- sh -c 'VAULT_TOKEN=<jeton> vault kv put secret/ows/grafana admin-user=admin admin-password=-'
# Forcer la resynchronisation sans attendre 1 h
kubectl -n monitoring annotate externalsecret grafana-admin force-sync=$(date +%s) --overwrite
```

Ajouter un secret pour une nouvelle application : écrire la valeur dans `secret/ows/<app>`, puis committer un `ExternalSecret` dans `gitops/manifests/external-secrets-config/` qui pointe vers ce chemin.

Desceller après un redémarrage (un pod Vault qui redémarre est scellé ; l'alerte `OWSVaultSealed` se déclenche) :

```bash
# Poser temporairement le fichier d'init, desceller, le détruire
./scripts/vault-bootstrap.sh unseal && shred -u ~/ows-secrets/vault-init.json
```

Sauvegarde de Vault : `vault operator raft snapshot save` (en plus de Velero, qui sauvegarde les PVC du namespace `vault`).

## Limites et améliorations

- **Descellement manuel** : sûr mais demande une intervention à chaque redémarrage de pod. En production, auto-unseal via un KMS (Transit d'un autre Vault, ou Barbican/HSM).
- **TLS interne désactivé** entre Vault et ses clients dans le cluster : acceptable dans un réseau de pods chiffrable par Cilium (WireGuard), mais à activer avec cert-manager en production.
- **Mot de passe admin ArgoCD** : généré par ArgoCD puis changé à la main ; peut passer par External Secrets (`argocd-secret`) dans une évolution.
