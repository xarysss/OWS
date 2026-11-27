data "openstack_networking_network_v2" "external" {
  name     = var.external_network_name
  external = true
}

resource "openstack_networking_network_v2" "k8s" {
  name           = "${var.prefix}-k8s-net"
  admin_state_up = true
  tags           = local.common_tags
}

resource "openstack_networking_subnet_v2" "k8s" {
  name            = "${var.prefix}-k8s-subnet"
  network_id      = openstack_networking_network_v2.k8s.id
  cidr            = var.subnet_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers
  tags            = local.common_tags

  # DHCP limité à .50-.190 : .10 (VIP), .11-.29 (nœuds) et la plage MetalLB
  # ne seront jamais attribués à une autre VM.
  allocation_pool {
    start = cidrhost(var.subnet_cidr, 50)
    end   = cidrhost(var.subnet_cidr, 190)
  }
}

resource "openstack_networking_router_v2" "k8s" {
  name                = "${var.prefix}-router"
  external_network_id = data.openstack_networking_network_v2.external.id
  tags                = local.common_tags
}

resource "openstack_networking_router_interface_v2" "k8s" {
  router_id = openstack_networking_router_v2.k8s.id
  subnet_id = openstack_networking_subnet_v2.k8s.id
}

# ---------- VIP de l'API (portée par kube-vip en ARP) ----------
# Port réservé, jamais attaché à une VM : il bloque l'adresse et porte l'IP flottante.
resource "openstack_networking_port_v2" "api_vip" {
  name           = "${var.prefix}-api-vip"
  network_id     = openstack_networking_network_v2.k8s.id
  admin_state_up = true
  security_group_ids = [openstack_networking_secgroup_v2.k8s.id]
  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.k8s.id
    ip_address = local.api_vip
  }
  tags = local.common_tags
}

resource "openstack_networking_floatingip_v2" "api_vip" {
  count       = var.api_floating_ip ? 1 : 0
  pool        = var.external_network_name
  description = "${var.prefix} API Kubernetes"
  tags        = local.common_tags
}

resource "openstack_networking_floatingip_associate_v2" "api_vip" {
  count       = var.api_floating_ip ? 1 : 0
  floating_ip = openstack_networking_floatingip_v2.api_vip[0].address
  port_id     = openstack_networking_port_v2.api_vip.id
  depends_on  = [openstack_networking_router_interface_v2.k8s]
}

# ---------- Adresses MetalLB exposées à l'extérieur ----------
resource "openstack_networking_port_v2" "lb" {
  for_each       = var.service_floating_ips
  name           = "${var.prefix}-lb-${each.key}"
  network_id     = openstack_networking_network_v2.k8s.id
  admin_state_up = true
  security_group_ids = [openstack_networking_secgroup_v2.ingress.id]
  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.k8s.id
    ip_address = cidrhost(var.subnet_cidr, each.value)
  }
  tags = local.common_tags
}

resource "openstack_networking_floatingip_v2" "lb" {
  for_each    = var.service_floating_ips
  pool        = var.external_network_name
  description = "${var.prefix} ${each.key}"
  tags        = local.common_tags
}

resource "openstack_networking_floatingip_associate_v2" "lb" {
  for_each    = var.service_floating_ips
  floating_ip = openstack_networking_floatingip_v2.lb[each.key].address
  port_id     = openstack_networking_port_v2.lb[each.key].id
  depends_on  = [openstack_networking_router_interface_v2.k8s]
}

# ---------- Bastion : IP flottante sur le premier control plane ----------
resource "openstack_networking_floatingip_v2" "bastion" {
  pool        = var.external_network_name
  description = "${var.prefix} bastion SSH (${local.cp_names[0]})"
  tags        = local.common_tags
}

resource "openstack_networking_floatingip_associate_v2" "bastion" {
  floating_ip = openstack_networking_floatingip_v2.bastion.address
  port_id     = openstack_networking_port_v2.node[local.cp_names[0]].id
  depends_on  = [openstack_networking_router_interface_v2.k8s]
}
