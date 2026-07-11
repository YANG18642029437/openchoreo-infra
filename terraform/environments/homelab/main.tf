locals {
  ssh_public_key = trimspace(file(var.ssh_public_key_path))
  dns_servers    = ["223.5.5.5", "1.1.1.1"]

  k3s_nodes = {
    ocp-node-01 = { vm_id = 120, address = "192.168.2.180/21" }
    ocp-node-02 = { vm_id = 121, address = "192.168.2.181/21" }
    ocp-node-03 = { vm_id = 122, address = "192.168.2.182/21" }
  }
}

resource "proxmox_virtual_environment_download_file" "ubuntu" {
  content_type       = "import"
  datastore_id       = var.image_datastore_id
  node_name          = var.node_name
  url                = var.ubuntu_image_url
  file_name          = "noble-server-cloudimg-amd64.img"
  checksum           = var.ubuntu_image_checksum
  checksum_algorithm = "sha256"
}

resource "proxmox_virtual_environment_vm" "ubuntu_template" {
  vm_id     = 9000
  name      = "ubuntu-2404-cloud-template"
  node_name = var.node_name
  pool_id   = "openchoreo"
  template  = true
  started   = false

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = var.system_datastore_id
    import_from  = proxmox_virtual_environment_download_file.ubuntu.id
    interface    = "scsi0"
    size         = 16
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  initialization {
    datastore_id = var.system_datastore_id

    user_account {
      username = "ubuntu"
      keys     = [local.ssh_public_key]
    }
  }

  serial_device {}

  lifecycle {
    prevent_destroy = true
  }
}

module "k3s_nodes" {
  source   = "../../modules/proxmox-cloud-vm"
  for_each = local.k3s_nodes

  node_name       = var.node_name
  vm_id           = each.value.vm_id
  name            = each.key
  template_vm_id  = proxmox_virtual_environment_vm.ubuntu_template.vm_id
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
  template_vm_id  = proxmox_virtual_environment_vm.ubuntu_template.vm_id
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
