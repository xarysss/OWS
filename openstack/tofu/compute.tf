resource "openstack_compute_keypair_v2" "ows" {
  name       = "${var.prefix}-admin"
  public_key = local.ssh_public_key
}

data "openstack_images_image_v2" "ubuntu" {
  name        = var.image_name
  most_recent = true
}

# Un port par nœud : adresse fixe + allowed-address-pairs.
#  - control planes : la VIP de l'API (kube-vip répond en ARP)
#  - workers        : la plage MetalLB (mode L2)
resource "openstack_networking_port_v2" "node" {
  for_each       = local.all_ips
  name           = "${each.key}-port"
  network_id     = openstack_networking_network_v2.k8s.id
  admin_state_up = true

  security_group_ids = concat(
    [openstack_networking_secgroup_v2.k8s.id],
    contains(local.worker_names, each.key) ? [openstack_networking_secgroup_v2.ingress.id] : []
  )

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.k8s.id
    ip_address = each.value
  }

  dynamic "allowed_address_pairs" {
    for_each = contains(local.cp_names, each.key) ? [local.api_vip] : [var.metallb_range.cidr]
    content {
      ip_address = allowed_address_pairs.value
    }
  }

  tags = local.common_tags
}

resource "openstack_compute_instance_v2" "node" {
  for_each    = local.all_ips
  name        = each.key
  flavor_name = contains(local.cp_names, each.key) ? var.flavor_control_plane : var.flavor_worker
  key_pair    = openstack_compute_keypair_v2.ows.name
  tags        = concat(local.common_tags, [contains(local.cp_names, each.key) ? "control-plane" : "worker"])

  block_device {
    uuid                  = data.openstack_images_image_v2.ubuntu.id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = var.boot_volume_size
    volume_type           = var.volume_type
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    port = openstack_networking_port_v2.node[each.key].id
  }

  user_data = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    hostname = each.key
    hosts    = local.all_ips
    api_vip  = local.api_vip
  })

  metadata = {
    role    = contains(local.cp_names, each.key) ? "control-plane" : "worker"
    project = "ows"
  }

  lifecycle {
    # Changer l'image ou le cloud-init ne doit pas détruire un nœud du cluster.
    ignore_changes = [user_data, block_device, image_id]
  }

  depends_on = [openstack_networking_router_interface_v2.k8s]
}

# ---------- Volumes OSD Ceph (vierges, un par worker) ----------
resource "openstack_blockstorage_volume_v3" "ceph" {
  for_each    = toset(local.worker_names)
  name        = "${each.key}-ceph-osd"
  size        = var.ceph_volume_size
  volume_type = var.volume_type
  description = "OSD Rook-Ceph, ne pas formater"
}

resource "openstack_compute_volume_attach_v2" "ceph" {
  for_each    = toset(local.worker_names)
  instance_id = openstack_compute_instance_v2.node[each.key].id
  volume_id   = openstack_blockstorage_volume_v3.ceph[each.key].id
}
