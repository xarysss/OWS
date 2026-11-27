# OpenStack (OpenTofu)

Infrastructure du cluster dans le projet OpenStack du groupe, décrite en OpenTofu dans `tofu/` :
réseau et routeur, groupes de sécurité, paire de clés, 6 VM Ubuntu 24.04 (3 CP + 3 workers),
volumes Ceph, port de VIP pour l'API (allowed-address-pairs).

- Toutes les ressources sont préfixées `ows-`.
- Authentification : `clouds.yaml` dans `~/.config/openstack/` sur le serveur, jamais dans Git.
  Modèle : [`clouds.yaml.example`](clouds.yaml.example).
- L'état OpenTofu (`*.tfstate`) et les `*.tfvars` réels ne sont pas versionnés
  (fournir un `*.tfvars.example`).

```bash
export OS_CLOUD=ows
cd openstack/tofu
tofu init && tofu plan && tofu apply   # détails : tofu/README.md
```
