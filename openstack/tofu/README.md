# Infrastructure OpenTofu (phase 3)

Crée dans le projet OpenStack `ows` tout ce dont le cluster Kubernetes a besoin. Toutes les
ressources sont préfixées `ows-`.

| Fichier | Contenu |
|---|---|
| `network.tf` | réseau `10.20.0.0/24`, routeur, port de la VIP API `.10` + IP flottante, ports MetalLB exposés, IP flottante bastion |
| `security.tf` | groupe `ows-k8s` (trafic interne, SSH et 6443 depuis `admin_cidrs`), groupe `ows-ingress` (80/443/8200) |
| `compute.tf` | paire de clés, VM Ubuntu 24.04 (CP `.11-.13`, workers `.21-.23`), volumes OSD Ceph vierges |
| `flavors.tf` | gabarits `ows.cp` / `ows.worker`, seulement si `create_flavors = true` |
| `inventory.tf` | génère `scripts/cluster.env`, `scripts/ssh_config`, `scripts/hosts.txt` pour `scripts/deploy-cluster.sh` |
| `check-ssh.sh` | vérifie SSH + fin de cloud-init sur chaque VM |

## Adresses

| Rôle | Adresse |
|---|---|
| VIP API (kube-vip) | 10.20.0.10, IP flottante associée |
| Control planes | 10.20.0.11 à .13 |
| Workers | 10.20.0.21 à .23 (volume OSD sur `/dev/vdb`) |
| DHCP Neutron | .50 à .190 (aucune collision possible avec les adresses fixes) |
| MetalLB | .200 à .223 ; ArgoCD .201, Grafana .202, Vault .203 avec IP flottante |

Le premier control plane porte l'IP flottante « bastion » ; les autres nœuds passent par lui
(`ProxyJump` dans `scripts/ssh_config`).

## Utilisation (sur os-compute-6, utilisateur `ows`, dans `/home/ows/OWS`)

Prérequis : `~/.config/openstack/clouds.yaml` (modèle `../clouds.yaml.example`), l'image
Ubuntu 24.04 et le réseau externe existent (audit, phase 2), la clé `~/.ssh/ows_ed25519`.

```bash
cd openstack/tofu
cp terraform.tfvars.example terraform.tfvars   # ajuster image, gabarits, réseau externe
export OS_CLOUD=ows
tofu init
tofu plan -out tfplan
tofu apply tfplan
cd ../.. && ./openstack/tofu/check-ssh.sh       # OK pour chaque nœud
./scripts/deploy-cluster.sh all                  # phase 4 : kubeadm
```

Rejouer de zéro : `tofu destroy` puis `tofu apply`. Les nœuds ont des clés `for_each`
stables : passer de 1 + 1 à 3 + 3 ajoute des VM sans recréer les premières, et changer
l'image ou le cloud-init ne détruit pas un nœud existant.

## Choix

- **VIP API** : port Neutron réservé, jamais attaché ; les control planes l'ont en
  allowed-address-pairs et kube-vip la répond en ARP. L'IP flottante suit donc le leader.
- **MetalLB (L2)** : les workers ont la plage `/27` et chaque IP de service exacte en
  allowed-address-pairs. Avec OVN, l'IP exacte fait passer le port réservé en type
  « virtual », ce qui rend son IP flottante joignable.
- **Disques** : démarrage sur volume Cinder (40 Go) et un volume vierge de 100 Go par worker
  pour Rook-Ceph. `boot_from_volume = false` et `ceph_volume_size = 0` si Cinder manque.
- **État** : local, jamais commité. Le fichier `.terraform.lock.hcl` l'est, pour figer
  les versions des fournisseurs.
