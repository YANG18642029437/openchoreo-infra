variable "node_name" {
  description = "Proxmox VE node that hosts the virtual machine."
  type        = string
}

variable "vm_id" {
  description = "Numeric Proxmox VE virtual machine identifier."
  type        = number
}

variable "name" {
  description = "Proxmox VE virtual machine name."
  type        = string
}

variable "template_vm_id" {
  description = "VM ID of the Ubuntu Cloud-Init template to clone."
  type        = number
}

variable "datastore_id" {
  description = "Datastore used for the virtual machine disks and Cloud-Init drive."
  type        = string
}

variable "cores" {
  description = "Number of virtual CPU cores."
  type        = number
}

variable "memory_mib" {
  description = "Dedicated memory in MiB."
  type        = number
}

variable "system_disk_gib" {
  description = "System disk size in GiB."
  type        = number

  validation {
    condition     = var.system_disk_gib >= 32
    error_message = "system_disk_gib must be at least 32 GiB."
  }
}

variable "data_disk_gib" {
  description = "Optional data disk size in GiB; zero disables the data disk."
  type        = number
  default     = 0

  validation {
    condition     = var.data_disk_gib >= 0
    error_message = "data_disk_gib cannot be negative."
  }
}

variable "data_disk_datastore_id" {
  description = "Optional datastore for the data disk; null uses datastore_id."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.data_disk_datastore_id == null ? true : (
      length(trimspace(var.data_disk_datastore_id)) > 0
    )
    error_message = "data_disk_datastore_id must be null or a non-empty datastore ID."
  }
}

variable "ipv4_address" {
  description = "Static IPv4 address in CIDR notation."
  type        = string
}

variable "ipv4_gateway" {
  description = "IPv4 default gateway."
  type        = string
}

variable "dns_servers" {
  description = "DNS servers supplied through Cloud-Init."
  type        = list(string)
}

variable "ssh_public_key" {
  description = "SSH public key installed for the Ubuntu user through Cloud-Init."
  type        = string
}

variable "bridge" {
  description = "Proxmox VE network bridge."
  type        = string
  default     = "vmbr0"
}
