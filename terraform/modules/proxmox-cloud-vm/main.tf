resource "proxmox_virtual_environment_vm" "this" {
  vm_id     = var.vm_id
  name      = var.name
  node_name = var.node_name
  pool_id   = "openchoreo"
  started   = true

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  stop_on_destroy = true

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mib
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.system_disk_gib
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  dynamic "disk" {
    for_each = var.data_disk_gib > 0 ? [var.data_disk_gib] : []

    content {
      datastore_id = var.datastore_id
      interface    = "scsi1"
      size         = disk.value
      iothread     = true
      discard      = "on"
      ssd          = true
    }
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  initialization {
    datastore_id = var.datastore_id

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }

  serial_device {}

  lifecycle {
    precondition {
      condition     = var.system_disk_gib >= 32
      error_message = "system disk must be at least 32 GiB"
    }
  }
}
