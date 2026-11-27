locals {
  cp_names     = [for i in range(1, var.control_plane_count + 1) : format("%s-cp-%d", var.prefix, i)]
  worker_names = [for i in range(1, var.worker_count + 1) : format("%s-worker-%d", var.prefix, i)]

  # Adresses fixes : CP .11-.13, workers .21-.23
  cp_ips     = { for i, n in local.cp_names : n => cidrhost(var.subnet_cidr, 11 + i) }
  worker_ips = { for i, n in local.worker_names : n => cidrhost(var.subnet_cidr, 21 + i) }
  all_ips    = merge(local.cp_ips, local.worker_ips)

  api_vip = cidrhost(var.subnet_cidr, var.api_vip_hostnum)

  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  # allowed-address-pairs des workers : la plage MetalLB + chaque IP de service exposée.
  worker_pairs = distinct(concat(
    [var.metallb_range.cidr],
    [for n in values(var.service_floating_ips) : cidrhost(var.subnet_cidr, n)]
  ))

  flavor_cp     = var.create_flavors ? openstack_compute_flavor_v2.cp[0].name : var.flavor_control_plane
  flavor_worker = var.create_flavors ? openstack_compute_flavor_v2.worker[0].name : var.flavor_worker

  common_tags = ["ows", "sae-cloud", "kubernetes"]
}
