variable "proxmox_endpoint" {
  description = "Proxmox VE API 地址。"
  type        = string
  default     = "https://192.168.2.162:8006/"
}

variable "proxmox_insecure" {
  description = "是否允许 Proxmox VE 使用自签名 TLS 证书。"
  type        = bool
  default     = true
}

variable "node_name" {
  description = "承载 OpenChoreo 虚拟机的 Proxmox VE 节点。"
  type        = string
  default     = "pve2162"
}

variable "system_datastore_id" {
  description = "保存虚拟机系统盘和数据盘的 Proxmox VE 存储。"
  type        = string
  default     = "XJ6T"
}

variable "k3s_etcd_datastore_id" {
  description = "保存 K3s embedded etcd 独立数据盘的 Proxmox VE 存储。"
  type        = string
  default     = "SSD1"

  validation {
    condition     = length(trimspace(var.k3s_etcd_datastore_id)) > 0
    error_message = "k3s_etcd_datastore_id 不能为空。"
  }
}

variable "template_vm_id" {
  description = "预先在 PVE 上创建的 Ubuntu Cloud-Init 模板 VM ID。"
  type        = number
  default     = 9000
}

variable "ssh_public_key_path" {
  description = "注入 Ubuntu 虚拟机的 SSH 公钥文件路径。"
  type        = string
}
