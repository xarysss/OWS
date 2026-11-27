# Groupe commun à tous les nœuds : tout le trafic interne est permis entre membres
# (etcd 2379-2380, kubelet 10250, VXLAN Cilium 8472/udp, santé Cilium 4240, BGP/ARP...).
resource "openstack_networking_secgroup_v2" "k8s" {
  name                 = "${var.prefix}-k8s"
  description          = "Nœuds Kubernetes OWS"
  delete_default_rules = false
  tags                 = local.common_tags
}

resource "openstack_networking_secgroup_rule_v2" "internal_ipv4" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_group_id   = openstack_networking_secgroup_v2.k8s.id
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

resource "openstack_networking_secgroup_rule_v2" "internal_subnet" {
  # Couvre aussi le trafic à destination de la VIP et des IP MetalLB.
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  for_each          = toset(var.admin_cidrs)
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

resource "openstack_networking_secgroup_rule_v2" "api" {
  for_each          = toset(var.admin_cidrs)
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  security_group_id = openstack_networking_secgroup_v2.k8s.id
}

# Services exposés par MetalLB (ArgoCD, Grafana, Vault...) : appliqué aux workers
# et aux ports réservés des IP flottantes.
resource "openstack_networking_secgroup_v2" "ingress" {
  name                 = "${var.prefix}-ingress"
  description          = "Services LoadBalancer OWS"
  delete_default_rules = false
  tags                 = local.common_tags
}

resource "openstack_networking_secgroup_rule_v2" "ingress_web" {
  for_each = {
    for pair in setproduct(var.ingress_cidrs, [80, 443, 8200]) :
    "${pair[0]}-${pair[1]}" => { cidr = pair[0], port = pair[1] }
  }
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = each.value.cidr
  security_group_id = openstack_networking_secgroup_v2.ingress.id
}
