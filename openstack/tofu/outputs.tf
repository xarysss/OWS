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

output "ceph_volumes" {
  description = "Volume OSD vierge attaché à chaque worker."
  value       = { for k, v in openstack_compute_volume_attach_v2.ceph : k => v.device }
}

output "ssh" {
  description = "Connexion aux nœuds (fichier généré par inventory.tf)."
  value       = "ssh -F scripts/ssh_config ${local.cp_names[0]}   # depuis la racine du dépôt"
}
