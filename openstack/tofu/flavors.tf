# Gabarits facultatifs (create_flavors = true) : utile sur le cloud tout-en-un où l'on est
# administrateur. Sur un cloud partagé, laisser false et donner des gabarits existants.
resource "openstack_compute_flavor_v2" "cp" {
  count     = var.create_flavors ? 1 : 0
  name      = var.flavor_control_plane
  vcpus     = var.flavor_specs.cp.vcpus
  ram       = var.flavor_specs.cp.ram
  disk      = var.flavor_specs.cp.disk
  is_public = true
}

resource "openstack_compute_flavor_v2" "worker" {
  count     = var.create_flavors ? 1 : 0
  name      = var.flavor_worker
  vcpus     = var.flavor_specs.worker.vcpus
  ram       = var.flavor_specs.worker.ram
  disk      = var.flavor_specs.worker.disk
  is_public = true
}
