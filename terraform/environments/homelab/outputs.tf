output "k3s_nodes" {
  description = "K3s 节点的 Proxmox VE VM ID 与静态 IPv4 地址。"
  value = {
    for name, node in module.k3s_nodes : name => {
      vm_id = node.vm_id
      ip    = node.ipv4_address
    }
  }
}

output "nfs_server" {
  description = "NFS 服务器的 Proxmox VE VM ID 与静态 IPv4 地址。"
  value = {
    vm_id = module.nfs_server.vm_id
    ip    = module.nfs_server.ipv4_address
  }
}

output "egress_gateway" {
  description = "出站代理网关的 Proxmox VE VM ID 与静态 IPv4 地址。"
  value = {
    vm_id = module.egress_gateway.vm_id
    ip    = module.egress_gateway.ipv4_address
  }
}
