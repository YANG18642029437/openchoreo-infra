output "vm_id" {
  description = "Proxmox VE virtual machine identifier."
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "ipv4_address" {
  description = "Configured static IPv4 address in CIDR notation."
  value       = var.ipv4_address
}
