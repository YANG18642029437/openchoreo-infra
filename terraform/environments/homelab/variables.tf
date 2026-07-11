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

variable "image_datastore_id" {
  description = "保存 Ubuntu Cloud Image 的 Proxmox VE 存储。"
  type        = string
  default     = "local"
}

variable "system_datastore_id" {
  description = "保存虚拟机系统盘和数据盘的 Proxmox VE 存储。"
  type        = string
  default     = "XJ6T"
}

variable "ubuntu_image_url" {
  description = "Ubuntu Noble AMD64 Cloud Image 下载地址。"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "ubuntu_image_checksum" {
  description = "Ubuntu Cloud Image 的 64 位小写十六进制 SHA-256 摘要。"
  type        = string

  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.ubuntu_image_checksum))
    error_message = "ubuntu_image_checksum must be a SHA-256 digest."
  }
}

variable "ssh_public_key_path" {
  description = "注入 Ubuntu 虚拟机的 SSH 公钥文件路径。"
  type        = string
}
