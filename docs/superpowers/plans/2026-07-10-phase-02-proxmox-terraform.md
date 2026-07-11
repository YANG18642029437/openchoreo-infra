# Phase 02 Proxmox Terraform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 使用 Ubuntu Cloud Image、Cloud-Init 和 Terraform 创建三台 K3s VM 与一台 NFS VM，并保留可独立恢复的旧 VM 全量备份。

**Architecture:** bpg/proxmox 下载并校验 Ubuntu Cloud Image，创建 VM9000 模板，然后完整克隆 VM120、121、122、130。任何删除动作都由单独的受保护脚本执行，Terraform apply 只在原 VM ID 已释放且用户完成最终确认后运行。

**Tech Stack:** Terraform 1.15.8、bpg/proxmox 0.111.1、Ubuntu Noble Cloud Image、Proxmox vzdump、Cloud-Init。

---

## 文件结构

- Create: terraform/environments/homelab/versions.tf
- Create: terraform/environments/homelab/provider.tf
- Create: terraform/environments/homelab/variables.tf
- Create: terraform/environments/homelab/main.tf
- Create: terraform/environments/homelab/outputs.tf
- Create: terraform/environments/homelab/backend.tf
- Create: terraform/environments/homelab/terraform.tfvars.example
- Create: terraform/modules/proxmox-cloud-vm/main.tf
- Create: terraform/modules/proxmox-cloud-vm/variables.tf
- Create: terraform/modules/proxmox-cloud-vm/outputs.tf
- Create: scripts/verify/terraform.sh
- Create: scripts/prepare/ubuntu-image-checksum.sh
- Create: scripts/backup/proxmox-vms.sh
- Create: scripts/verify/proxmox-backups.sh
- Create: scripts/change/remove-old-vms.sh
- Create: scripts/verify/virtual-machines.sh
- Create: runbooks/10-proxmox-rebuild.md

## Task 1: 先写 Terraform 契约检查

**Files:**

- Create: scripts/verify/terraform.sh

- [ ] **Step 1: 写会失败的验证脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tf_dir="$repo_root/terraform/environments/homelab"

required=(
  versions.tf
  provider.tf
  variables.tf
  main.tf
  outputs.tf
  backend.tf
  terraform.tfvars.example
)

for file in "${required[@]}"; do
  test -f "$tf_dir/$file" || {
    printf 'missing Terraform file: %s\n' "$file" >&2
    exit 1
  }
done

terraform -chdir="$tf_dir" fmt -check -recursive
terraform -chdir="$tf_dir" init -backend=false
terraform -chdir="$tf_dir" validate

if rg -n 'latest|main|master' "$tf_dir" "$repo_root/terraform/modules"; then
  printf 'unlocked version found in Terraform\n' >&2
  exit 1
fi

printf 'terraform static validation: PASS\n'
~~~

- [ ] **Step 2: 运行并确认失败**

~~~bash
chmod +x scripts/verify/terraform.sh
./scripts/verify/terraform.sh
~~~

Expected: missing Terraform file: versions.tf。

- [ ] **Step 3: 提交测试**

~~~bash
git add scripts/verify/terraform.sh
git commit -m "test: define Terraform infrastructure contract"
~~~

## Task 2: 创建 Terraform Provider 和变量

**Files:**

- Create: terraform/environments/homelab/versions.tf
- Create: terraform/environments/homelab/provider.tf
- Create: terraform/environments/homelab/variables.tf
- Create: terraform/environments/homelab/backend.tf

- [ ] **Step 1: 写 versions.tf**

~~~hcl
terraform {
  required_version = "= 1.15.8"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "= 0.111.1"
    }
  }
}
~~~

- [ ] **Step 2: 写 provider.tf**

~~~hcl
provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure

  ssh {
    agent    = true
    username = var.proxmox_ssh_username
  }
}
~~~

Provider API Token 只通过 PROXMOX_VE_API_TOKEN 环境变量提供。

- [ ] **Step 3: 写 backend.tf**

~~~hcl
terraform {
  backend "local" {
    path = "../../../.private/terraform-state/homelab.tfstate"
  }
}
~~~

- [ ] **Step 4: 写 variables.tf**

~~~hcl
variable "proxmox_endpoint" {
  type    = string
  default = "https://192.168.2.162:8006/"
}

variable "proxmox_insecure" {
  type    = bool
  default = true
}

variable "proxmox_ssh_username" {
  type    = string
  default = "root"
}

variable "node_name" {
  type    = string
  default = "pve2162"
}

variable "image_datastore_id" {
  type    = string
  default = "local"
}

variable "system_datastore_id" {
  type    = string
  default = "XJ6T"
}

variable "ubuntu_image_url" {
  type    = string
  default = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "ubuntu_image_checksum" {
  type      = string
  sensitive = false

  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.ubuntu_image_checksum))
    error_message = "ubuntu_image_checksum must be a SHA-256 digest."
  }
}

variable "ssh_public_key_path" {
  type = string
}
~~~

- [ ] **Step 5: 格式化并提交**

~~~bash
terraform -chdir=terraform/environments/homelab fmt
git add terraform/environments/homelab/{versions.tf,provider.tf,variables.tf,backend.tf}
git commit -m "feat: configure Proxmox Terraform provider"
~~~

## Task 3: 创建可复用 Cloud VM 模块

**Files:**

- Create: terraform/modules/proxmox-cloud-vm/variables.tf
- Create: terraform/modules/proxmox-cloud-vm/main.tf
- Create: terraform/modules/proxmox-cloud-vm/outputs.tf

- [ ] **Step 1: 写 variables.tf**

~~~hcl
variable "node_name" { type = string }
variable "vm_id" { type = number }
variable "name" { type = string }
variable "template_vm_id" { type = number }
variable "datastore_id" { type = string }
variable "cores" { type = number }
variable "memory_mib" { type = number }
variable "system_disk_gib" { type = number }
variable "data_disk_gib" {
  type    = number
  default = 0
}
variable "ipv4_address" { type = string }
variable "ipv4_gateway" { type = string }
variable "dns_servers" { type = list(string) }
variable "ssh_public_key" { type = string }
variable "bridge" {
  type    = string
  default = "vmbr0"
}
~~~

- [ ] **Step 2: 写 main.tf**

~~~hcl
resource "proxmox_virtual_environment_vm" "this" {
  vm_id     = var.vm_id
  name      = var.name
  node_name = var.node_name
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
~~~

- [ ] **Step 3: 写 outputs.tf**

~~~hcl
output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "ipv4_address" {
  value = var.ipv4_address
}
~~~

- [ ] **Step 4: 格式化并提交**

~~~bash
terraform fmt -recursive terraform/modules
git add terraform/modules/proxmox-cloud-vm
git commit -m "feat: add reusable Proxmox cloud VM module"
~~~

## Task 4: 创建 Cloud Image 模板与四台 VM

**Files:**

- Create: terraform/environments/homelab/main.tf
- Create: terraform/environments/homelab/outputs.tf
- Create: terraform/environments/homelab/terraform.tfvars.example

- [ ] **Step 1: 写 main.tf 的模板资源**

~~~hcl
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
  file_name          = "noble-server-cloudimg-amd64.qcow2"
  checksum           = var.ubuntu_image_checksum
  checksum_algorithm = "sha256"
}

resource "proxmox_virtual_environment_vm" "ubuntu_template" {
  vm_id     = 9000
  name      = "ubuntu-2404-cloud-template"
  node_name = var.node_name
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
~~~

- [ ] **Step 2: 在同一 main.tf 增加 K3s VM**

~~~hcl
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
}
~~~

- [ ] **Step 3: 增加 NFS VM**

~~~hcl
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
}
~~~

- [ ] **Step 4: 写 outputs.tf**

~~~hcl
output "k3s_nodes" {
  value = {
    for name, node in module.k3s_nodes : name => {
      vm_id = node.vm_id
      ip    = node.ipv4_address
    }
  }
}

output "nfs_server" {
  value = {
    vm_id = module.nfs_server.vm_id
    ip    = module.nfs_server.ipv4_address
  }
}
~~~

- [ ] **Step 5: 写 terraform.tfvars.example**

~~~hcl
ubuntu_image_checksum = "replace-with-64-character-sha256"
ssh_public_key_path   = "../../../.private/ssh/id_ed25519.pub"
~~~

此文件是示例，不复制成仓库内可跟踪文件。真实变量通过 TF_VAR_ubuntu_image_checksum 和 TF_VAR_ssh_public_key_path 提供。

- [ ] **Step 6: 验证并提交**

~~~bash
./scripts/verify/terraform.sh
git add terraform/environments/homelab
git commit -m "feat: define OpenChoreo Proxmox virtual machines"
~~~

Expected: terraform static validation: PASS。

## Task 5: 解析 Ubuntu Cloud Image 校验值

**Files:**

- Create: scripts/prepare/ubuntu-image-checksum.sh

- [ ] **Step 1: 写校验值脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail

base_url="https://cloud-images.ubuntu.com/noble/current"
image="noble-server-cloudimg-amd64.img"
private_dir=".private/credentials"
env_file="$private_dir/terraform.env"

install -d -m 0700 "$private_dir"
checksum="$(curl -fsSL "$base_url/SHA256SUMS" | awk -v image="$image" '$2 == image {print $1}')"

test "${#checksum}" -eq 64

umask 077
{
  printf 'export TF_VAR_ubuntu_image_checksum=%q\n' "$checksum"
  printf 'export TF_VAR_ssh_public_key_path=%q\n' "../../../.private/ssh/id_ed25519.pub"
} > "$env_file"

printf 'wrote %s\n' "$env_file"
~~~

- [ ] **Step 2: 验证脚本但不下载镜像**

~~~bash
chmod +x scripts/prepare/ubuntu-image-checksum.sh
bash -n scripts/prepare/ubuntu-image-checksum.sh
git add scripts/prepare/ubuntu-image-checksum.sh
git commit -m "feat: resolve Ubuntu cloud image checksum"
~~~

## Task 6: 创建 vzdump 全量备份脚本

**Files:**

- Create: scripts/backup/proxmox-vms.sh
- Create: scripts/verify/proxmox-backups.sh

- [ ] **Step 1: 写备份脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail

pve_host="${PVE_SSH_HOST:-root@192.168.2.162}"
storage="${PVE_BACKUP_STORAGE:-PvEDump}"
stamp="$(date +%Y%m%d-%H%M%S)"

for vmid in 120 121 122; do
  ssh "$pve_host" \
    "vzdump $vmid --storage $storage --mode snapshot --compress zstd --remove 0 --notes-template 'pre-terraform-$stamp'"
done
~~~

- [ ] **Step 2: 写备份验证脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail

pve_host="${PVE_SSH_HOST:-root@192.168.2.162}"
storage="${PVE_BACKUP_STORAGE:-PvEDump}"

for vmid in 120 121 122; do
  ssh "$pve_host" "
    set -e
    volume=\$(pvesm list '$storage' --content backup |
      awk '/vzdump-qemu-$vmid-/ {print \$1}' |
      tail -1)
    test -n \"\$volume\"
    path=\$(pvesm path \"\$volume\")
    test -s \"\$path\"
    zstd -t \"\$path\"
    printf 'BACKUP_OK vmid=$vmid volume=%s\n' \"\$volume\"
  "
done
~~~

- [ ] **Step 3: 语法验证和提交**

~~~bash
chmod +x scripts/backup/proxmox-vms.sh scripts/verify/proxmox-backups.sh
bash -n scripts/backup/proxmox-vms.sh
bash -n scripts/verify/proxmox-backups.sh
git add scripts/backup scripts/verify/proxmox-backups.sh
git commit -m "feat: add verified Proxmox full backups"
~~~

## Task 7: 创建受保护的删除脚本

**Files:**

- Create: scripts/change/remove-old-vms.sh

- [ ] **Step 1: 写双重确认脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail

if test "${ALLOW_DESTRUCTIVE_REBUILD:-}" != "CONFIRMED_BY_USER"; then
  printf 'refusing destructive rebuild without ALLOW_DESTRUCTIVE_REBUILD\n' >&2
  exit 1
fi

pve_host="${PVE_SSH_HOST:-root@192.168.2.162}"

for vmid in 120 121 122; do
  ssh "$pve_host" "
    set -e
    if qm config $vmid | grep '^scsi1:' >/dev/null; then
      qm set $vmid --delete scsi1
    fi
    qm stop $vmid --timeout 120 || true
    qm destroy $vmid --purge 1 --destroy-unreferenced-disks 1
  "
done
~~~

- [ ] **Step 2: 验证默认拒绝**

~~~bash
chmod +x scripts/change/remove-old-vms.sh
if scripts/change/remove-old-vms.sh 2>&1 | rg 'refusing destructive rebuild'; then
  printf 'destructive guard: PASS\n'
else
  exit 1
fi
~~~

Expected: 不连接远程，输出 destructive guard: PASS。

- [ ] **Step 3: 提交**

~~~bash
git add scripts/change/remove-old-vms.sh
git commit -m "feat: guard destructive VM replacement"
~~~

## Task 8: 生成 Terraform plan

- [ ] **Step 1: 加载本地变量**

~~~bash
./scripts/prepare/ubuntu-image-checksum.sh
source .private/credentials/proxmox.env
source .private/credentials/terraform.env
~~~

- [ ] **Step 2: 初始化并生成 plan**

~~~bash
terraform -chdir=terraform/environments/homelab init
terraform -chdir=terraform/environments/homelab plan \
  -out=.private/terraform-state/homelab.tfplan
terraform -chdir=terraform/environments/homelab show \
  -no-color .private/terraform-state/homelab.tfplan \
  > .private/terraform-state/homelab.plan.txt
~~~

Expected: 计划包含模板 9000、VM120、121、122、130，不包含其他 VM。

- [ ] **Step 3: 到达停止点 B**

将 plan 摘要、IP 审计、空盘证据和存储容量交给用户。没有用户确认不得继续。

## Task 9: 创建并验证全量备份

- [ ] **Step 1: 运行 vzdump**

~~~bash
./scripts/backup/proxmox-vms.sh
~~~

Expected: 三个 vzdump 任务返回 TASK OK。

- [ ] **Step 2: 验证备份**

~~~bash
./scripts/verify/proxmox-backups.sh | tee .private/backups/vzdump-verification.txt
~~~

Expected: VM120、121、122 各有一行 BACKUP_OK。

- [ ] **Step 3: 到达停止点 C 和 D**

重新展示：

- 三个 BACKUP_OK。
- scsi1 空盘证据。
- Terraform plan。
- qmrestore 回滚方式。

等待用户明确确认。

## Task 10: 删除旧 VM 并执行 Terraform

此任务是不可逆停止点之后的执行任务。

- [ ] **Step 1: 删除旧 VM**

~~~bash
ALLOW_DESTRUCTIVE_REBUILD=CONFIRMED_BY_USER \
  ./scripts/change/remove-old-vms.sh
~~~

Expected: qm status 120、121、122 均返回不存在。

- [ ] **Step 2: 执行已保存 plan**

~~~bash
terraform -chdir=terraform/environments/homelab apply \
  .private/terraform-state/homelab.tfplan
~~~

Expected: Apply complete，创建模板和四台 VM。

- [ ] **Step 3: 不执行 terraform destroy**

任何失败使用定向修复或 qmrestore；禁止为了重试运行 terraform destroy。

## Task 11: 验证四台 VM

**Files:**

- Create: scripts/verify/virtual-machines.sh

- [ ] **Step 1: 写 VM 验证脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail

while read -r ip min_cpu min_mem; do
  ssh -o BatchMode=yes "ubuntu@$ip" "
    set -e
    test \$(nproc) -ge $min_cpu
    test \$(free -g | awk '/Mem:/ {print \$2}') -ge $min_mem
    test \$(findmnt -n -o FSTYPE /) != ''
    cloud-init status --wait
  "
done <<'HOSTS'
192.168.2.180 4 15
192.168.2.181 4 15
192.168.2.182 4 15
192.168.2.183 2 3
HOSTS

ssh ubuntu@192.168.2.183 \
  "lsblk -b -n -o SIZE,TYPE | awk '\$2==\"disk\" && \$1 >= 400000000000 {found=1} END {exit !found}'"

printf 'virtual machines: PASS\n'
~~~

- [ ] **Step 2: 运行验证**

~~~bash
chmod +x scripts/verify/virtual-machines.sh
./scripts/verify/virtual-machines.sh
~~~

Expected: virtual machines: PASS。

- [ ] **Step 3: 提交验证和 Runbook**

runbooks/10-proxmox-rebuild.md 必须记录备份、删除、Terraform apply 和 qmrestore 命令。

~~~bash
git add scripts/verify/virtual-machines.sh runbooks/10-proxmox-rebuild.md
git commit -m "test: verify Terraform provisioned virtual machines"
git push origin codex/openchoreo-platform
~~~

完成后停止，不安装 K3s；进入 Phase 03 前先审阅 VM 和备份证据。
