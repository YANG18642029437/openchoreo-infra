locals {
  ssh_public_key = trimspace(file(var.ssh_public_key_path))
  dns_servers    = ["223.5.5.5", "1.1.1.1"]

  k3s_nodes = {
    ocp-node-01 = { vm_id = 120, address = "192.168.2.180/21" }
    ocp-node-02 = { vm_id = 121, address = "192.168.2.181/21" }
    ocp-node-03 = { vm_id = 122, address = "192.168.2.182/21" }
  }
}

module "k3s_nodes" {
  source   = "../../modules/proxmox-cloud-vm"
  for_each = local.k3s_nodes

  node_name       = var.node_name
  vm_id           = each.value.vm_id
  name            = each.key
  template_vm_id  = var.template_vm_id
  datastore_id    = var.system_datastore_id
  cores           = 4
  memory_mib      = 16384
  system_disk_gib = 100
  ipv4_address    = each.value.address
  ipv4_gateway    = "192.168.1.1"
  dns_servers     = local.dns_servers
  ssh_public_key  = local.ssh_public_key
  bridge          = "vmbr0"
}

module "nfs_server" {
  source = "../../modules/proxmox-cloud-vm"

  node_name       = var.node_name
  vm_id           = 130
  name            = "nfs-storage-01"
  template_vm_id  = var.template_vm_id
  datastore_id    = var.system_datastore_id
  cores           = 2
  memory_mib      = 4096
  system_disk_gib = 32
  data_disk_gib   = 400
  ipv4_address    = "192.168.2.183/21"
  ipv4_gateway    = "192.168.1.1"
  dns_servers     = local.dns_servers
  ssh_public_key  = local.ssh_public_key
  bridge          = "vmbr0"
}

module "egress_gateway" {
  source = "../../modules/proxmox-cloud-vm"

  node_name       = var.node_name
  vm_id           = 131
  name            = "egress-gateway-01"
  template_vm_id  = var.template_vm_id
  datastore_id    = var.system_datastore_id
  cores           = 2
  memory_mib      = 2048
  system_disk_gib = 32
  ipv4_address    = "192.168.2.184/21"
  ipv4_gateway    = "192.168.1.1"
  dns_servers     = local.dns_servers
  ssh_public_key  = local.ssh_public_key
  bridge          = "vmbr0"
}
