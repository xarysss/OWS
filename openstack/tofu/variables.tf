variable "os_cloud" {
  description = "Nom de l'entrée dans clouds.yaml (identifiant d'application Horizon)."
  type        = string
  default     = "ows"
}

variable "prefix" {
  description = "Préfixe de toutes les ressources (cloud partagé)."
  type        = string
  default     = "ows"
}

# ---------- Taille du cluster ----------
# Cible : 3 control planes (.11-.13) + 3 workers (.21-.23).
# Pour un essai rapide : 1 + 1. Passer de 1 à 3 ne recrée pas les nœuds existants
# (for_each à clés stables).
variable "control_plane_count" {
  type    = number
  default = 3
  validation {
    condition     = contains([1, 3], var.control_plane_count)
    error_message = "1 (phase validation) ou 3 (HA, quorum etcd)."
  }
}

variable "worker_count" {
  type    = number
  default = 3
  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 3
    error_message = "Entre 1 et 3 workers."
  }
}

# ---------- Image et gabarits (noms à confirmer à l'audit du projet, phase 2) ----------
variable "image_name" {
  description = "Image Glance Ubuntu 24.04 (openstack image list)."
  type        = string
  default     = "ubuntu-24.04"
}

variable "flavor_control_plane" {
  description = "Gabarit CP visé : 3 vCPU / 8 Go (openstack flavor list)."
  type        = string
  default     = "ows.cp"
}

variable "flavor_worker" {
  description = "Gabarit worker visé : 4 vCPU / 12-16 Go."
  type        = string
  default     = "ows.worker"
}

variable "create_flavors" {
  description = "Créer les gabarits ows.cp et ows.worker (droits admin, cloud tout-en-un). false = gabarits existants."
  type        = bool
  default     = false
}

variable "flavor_specs" {
  description = "Taille des gabarits créés si create_flavors = true (RAM en Mo, disque racine en Go)."
  type = map(object({
    vcpus = number
    ram   = number
    disk  = number
  }))
  default = {
    cp     = { vcpus = 3, ram = 8192, disk = 40 }
    worker = { vcpus = 4, ram = 16384, disk = 40 }
  }
}

variable "boot_from_volume" {
  description = "Disque système sur un volume Cinder (true) ou disque éphémère Nova (false)."
  type        = bool
  default     = true
}

variable "boot_volume_size" {
  description = "Taille du disque système (Go), démarrage sur volume Cinder."
  type        = number
  default     = 40
}

variable "ceph_volume_size" {
  description = "Volume vierge par worker pour un OSD Ceph (Go). 0 = pas de volume."
  type        = number
  default     = 100
  validation {
    condition     = var.ceph_volume_size == 0 || var.ceph_volume_size >= 10
    error_message = "0 (désactivé) ou au moins 10 Go."
  }
}

variable "volume_type" {
  description = "Type de volume Cinder (null = défaut du cloud)."
  type        = string
  default     = null
}

# ---------- Réseau ----------
variable "external_network_name" {
  description = "Réseau externe pour le routeur et les IP flottantes (openstack network list --external)."
  type        = string
  default     = "public"
}

variable "dns_nameservers" {
  type    = list(string)
  default = ["1.1.1.1", "9.9.9.9"]
}

variable "subnet_cidr" {
  description = "Réseau des nœuds. Ne doit chevaucher ni 10.244.0.0/16 (pods) ni 10.96.0.0/12 (services)."
  type        = string
  default     = "10.20.0.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 254)) && !contains(["10.244.0.0/16", "10.96.0.0/12"], var.subnet_cidr)
    error_message = "CIDR IPv4 d'au moins /24, distinct des réseaux pods et services."
  }
}

variable "api_vip_hostnum" {
  description = "Numéro d'hôte de la VIP de l'API Kubernetes (kube-vip) : 10.20.0.10."
  type        = number
  default     = 10
}

variable "metallb_range" {
  description = "Plage MetalLB, exclue du DHCP Neutron et autorisée par allowed-address-pairs sur les workers."
  type = object({
    first_hostnum = number
    last_hostnum  = number
    cidr          = string # CIDR couvrant la plage, pour allowed_address_pairs
  })
  default = {
    first_hostnum = 200
    last_hostnum  = 223
    cidr          = "10.20.0.192/27"
  }
  validation {
    condition     = var.metallb_range.first_hostnum > 190 && var.metallb_range.first_hostnum <= var.metallb_range.last_hostnum && var.metallb_range.last_hostnum < 255
    error_message = "La plage MetalLB doit être hors du DHCP (.50-.190) et croissante."
  }
}

variable "admin_cidrs" {
  description = "CIDR autorisés en SSH et sur l'API (réseau de l'IUT / os-compute-6)."
  type        = list(string)
  default     = ["10.202.100.0/24"]
}

variable "ingress_cidrs" {
  description = "CIDR autorisés vers les services exposés par MetalLB (80/443)."
  type        = list(string)
  default     = ["10.202.0.0/16"]
}

variable "ssh_public_key_path" {
  description = "Clé publique déposée sur les VM (utilisateur ubuntu)."
  type        = string
  default     = "~/.ssh/ows_ed25519.pub"
}

variable "api_floating_ip" {
  description = "Associer une IP flottante à la VIP de l'API (kubectl depuis l'extérieur)."
  type        = bool
  default     = true
}

variable "service_floating_ips" {
  description = "Adresses MetalLB (numéros d'hôte) qui reçoivent une IP flottante : ArgoCD, Grafana, Vault."
  type        = map(number)
  default = {
    argocd  = 201
    grafana = 202
    vault   = 203
  }
  validation {
    condition     = alltrue([for n in values(var.service_floating_ips) : n >= var.metallb_range.first_hostnum && n <= var.metallb_range.last_hostnum])
    error_message = "Chaque adresse de service doit être dans la plage MetalLB."
  }
}
