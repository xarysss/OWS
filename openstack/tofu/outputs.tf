output "bastion_ip" {
  description = "IP flottante SSH (premier control plane)."
  value       = openstack_networking_floatingip_v2.bastion.address
}

output "api_vip" {
  value = local.api_vip
}

output "api_floating_ip" {
  value = var.api_floating_ip ? openstack_networking_floatingip_v2.api_vip[0].address : null
}

output "control_planes" {
  value = local.cp_ips
}

output "workers" {
  value = local.worker_ips
}

output "service_floating_ips" {
  description = "Service => IP flottante publique (=> IP MetalLB interne)."
  value = {
    for k, v in var.service_floating_ips :
    k => "${openstack_networking_floatingip_v2.lb[k].address} -> ${cidrhost(var.subnet_cidr, v)}"
  }
}

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
