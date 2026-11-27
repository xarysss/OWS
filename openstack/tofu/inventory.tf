# Inventaire pour les scripts kubeadm (scripts/deploy-cluster.sh), régénéré à chaque apply.
# Aucun secret dedans ; ces fichiers sont ignorés par Git (.gitignore).

# Fichier lu par scripts/deploy-cluster.sh (aucun secret dedans).
resource "local_file" "cluster_env" {
  filename        = "${path.module}/../../scripts/cluster.env"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/cluster.env.tftpl", {
    bastion         = openstack_networking_floatingip_v2.bastion.address
    api_vip         = local.api_vip
    api_floating_ip = var.api_floating_ip ? openstack_networking_floatingip_v2.api_vip[0].address : ""
    cps             = local.cp_ips
    workers         = local.worker_ips
    subnet_cidr     = var.subnet_cidr
    metallb_first   = cidrhost(var.subnet_cidr, var.metallb_range.first_hostnum)
    metallb_last    = cidrhost(var.subnet_cidr, var.metallb_range.last_hostnum)
  })
}

resource "local_file" "ssh_config" {
  filename        = "${path.module}/../../scripts/ssh_config"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/ssh_config.tftpl", {
    bastion = openstack_networking_floatingip_v2.bastion.address
    nodes   = local.all_ips
    first   = local.cp_names[0]
  })
}

# Liste simple « nom ip rôle », pratique pour les boucles shell (check-ssh.sh).
resource "local_file" "hosts" {
  filename        = "${path.module}/../../scripts/hosts.txt"
  file_permission = "0644"
  content = join("", concat(
    [for n, ip in local.cp_ips : "${n} ${ip} control-plane\n"],
    [for n, ip in local.worker_ips : "${n} ${ip} worker\n"]
  ))
}
