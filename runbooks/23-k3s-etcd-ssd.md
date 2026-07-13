# 如何把 K3s embedded etcd 迁移到 SSD

本 Runbook 为 VM 120–122 分别创建一块位于 PVE `SSD1` 的 20 GiB `scsi1`，再逐节点把 `/var/lib/rancher/k3s/server/db` 迁移到对应 SSD。三台 VM 使用同一块物理 SSD，但不共享虚拟磁盘、文件系统或 etcd 数据目录。

## 边界与停止点

- Terraform 只允许更新 `ocp-node-01`、`ocp-node-02`、`ocp-node-03`，每台新增一块 `20 GiB @ SSD1` 的 `scsi1`。
- `terraform apply` 必须使用经过验证的保存 plan，并在执行时重新取得明确确认。
- 来宾磁盘格式化、停止 K3s 和数据迁移必须按单节点分别确认；一次确认不能覆盖三台节点。
- 专用 playbook 强制只接受一个 `--limit` 目标，不会进入 `ansible/playbooks/site.yml`。
- 原机械盘数据不会自动删除，Terraform 也不会在回滚中自动删除 `scsi1`。

## 前置条件

从仓库根目录执行，并确认以下受保护文件存在：

```bash
test -f .private/ssh/openchoreo_ed25519
test -f .private/ssh/openchoreo_ed25519.pub
test -f .private/tokens/proxmox-terraform.token
test -f .private/kubeconfigs/homelab-admin.yaml
test -f .private/terraform-state/homelab.tfstate
```

设置本地工具与凭据路径。命令不会打印 Token 内容：

```bash
umask 077
export PATH="$PWD/.private/ansible-venv/bin:$PATH"
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
export ANSIBLE_SSH_ARGS="-o UserKnownHostsFile=$PWD/.private/known_hosts -o StrictHostKeyChecking=yes"
export OPENCHOREO_SSH_KEY="$PWD/.private/ssh/openchoreo_ed25519"
export KUBECONFIG="$PWD/.private/kubeconfigs/homelab-admin.yaml"
export TF_VAR_ssh_public_key_path="$PWD/.private/ssh/openchoreo_ed25519.pub"
export PROXMOX_VE_ENDPOINT='https://192.168.2.162:8006/'
export PROXMOX_VE_INSECURE=true
export PROXMOX_VE_API_TOKEN="$(<.private/tokens/proxmox-terraform.token)"
```

先运行本地门禁：

```bash
./scripts/verify/terraform.sh
./scripts/verify/etcd-ssd.sh
./scripts/verify/ansible.sh
./scripts/verify/phase01.sh
```

## 生成并验证 Terraform plan

创建受保护的保存 plan 和原始证据：

```bash
install -d -m 0700 .private/terraform-plans .private/evidence
plan_file="$PWD/.private/terraform-plans/k3s-etcd-ssd.tfplan"
evidence_file="$PWD/.private/evidence/$(date +%Y-%m-%d-%H%M)-k3s-etcd-ssd-plan.txt"

set -o pipefail
terraform -chdir=terraform/environments/homelab plan \
  -input=false \
  -out="$plan_file" \
  2>&1 | tee "$evidence_file"

./scripts/verify/terraform-etcd-ssd-plan.sh "$plan_file"
shasum -a 256 "$plan_file"
```

验证器必须输出 `Terraform etcd SSD plan: PASS`。出现 delete、replace、现有磁盘变化、无关资源变化或目标集合不完整时立即停止。

### 停止点 A：Terraform apply

即使 plan 验证通过，也不能自动 apply。记录 plan 路径、SHA-256 和验证结果，取得新的明确确认后，只能应用同一个保存 plan：

```bash
terraform -chdir=terraform/environments/homelab apply \
  -input=false \
  "$plan_file"
```

不得重新生成一个未验证的 plan 后直接 apply。

## 只读审计单个来宾磁盘

Terraform apply 完成后，先取得实时只读审计确认，再对第一台节点运行默认关闭格式化的 playbook：

```bash
ansible-playbook -i inventory/hosts.yaml \
  ansible/playbooks/36-k3s-etcd-ssd.yml \
  --limit ocp-node-01
```

预期在读取 `findmnt` 与 `lsblk` 后主动失败，错误提示要求显式设置 `k3s_etcd_ssd_allow_format=true`。在此失败点之前不会创建 snapshot、停止 K3s、格式化或挂载磁盘。

以下任一条件不满足都不得继续：

- 目标节点恰好存在一块 19–21 GiB 非根磁盘；
- 磁盘没有文件系统和挂载点；
- 当前 Kubernetes Node 为 `Ready`；
- 审计目标与 Terraform 新增的 `scsi1` 一致。

### 停止点 B：VM120 格式化与迁移

取得 VM120 的格式化、停服和迁移确认后执行：

```bash
ansible-playbook -i inventory/hosts.yaml \
  ansible/playbooks/36-k3s-etcd-ssd.yml \
  --limit ocp-node-01 \
  -e k3s_etcd_ssd_allow_format=true
```

Role 会创建并验证 etcd snapshot，停止当前节点 K3s，再次核对目标盘，创建 ext4，复制数据并建立 bind mount。迁移块中途失败时，`always` 恢复任务仍会尝试启动 K3s；整个 play 保持失败，不会处理下一节点。

## 验证当前节点

迁移命令自身必须完成以下门禁：

- 当前 Node 恢复 `Ready`；
- 控制机访问 `/readyz?verbose` 包含 `[+]etcd ok`；
- 当前节点本地 `k3s kubectl get --raw=/readyz?verbose` 包含 `[+]etcd ok`；
- `/var/lib/rancher/k3s/server/db` 是 bind mount；
- SSD 数据目录的底层文件系统是 ext4。

再执行只读汇总检查：

```bash
kubectl get nodes -o wide
kubectl get --raw=/readyz?verbose | grep -F '[+]etcd ok'

ansible -i inventory/hosts.yaml ocp-node-01 -b -m ansible.builtin.command \
  -a 'findmnt -rn -M /var/lib/rancher/k3s/server/db -o TARGET,OPTIONS'
ansible -i inventory/hosts.yaml ocp-node-01 -b -m ansible.builtin.command \
  -a 'findmnt -rn -T /var/lib/rancher/k3s-ssd/db -o SOURCE,FSTYPE'
ansible -i inventory/hosts.yaml ocp-node-01 -b -m ansible.builtin.command \
  -a 'k3s kubectl get --raw=/readyz?verbose'
```

如果验证失败，停止批次并按回滚章节处理，不得迁移下一台。

## 逐台迁移 VM121 和 VM122

VM120 全部验证通过后，分别为 VM121、VM122 取得新的执行确认。每台都先运行不带格式化开关的审计命令，再运行带开关的迁移命令：

```bash
ansible-playbook -i inventory/hosts.yaml \
  ansible/playbooks/36-k3s-etcd-ssd.yml \
  --limit ocp-node-02

ansible-playbook -i inventory/hosts.yaml \
  ansible/playbooks/36-k3s-etcd-ssd.yml \
  --limit ocp-node-02 \
  -e k3s_etcd_ssd_allow_format=true
```

VM121 验证通过后，再对 `ocp-node-03` 执行同样的审计、确认、迁移和验证流程。不要去掉 `--limit`，也不要并行执行。

## 回滚

回滚也是远程写操作，必须先取得新的明确确认。保持另外两台节点不变，不删除 `scsi1` 或 SSD 文件系统。

### K3s 从未在 SSD bind mount 上启动

仅当确认 K3s 从未在新 bind mount 上成功启动时，机械盘下的原目录仍是最新副本，可使用最小回滚：

```bash
sudo systemctl stop k3s
sudo umount /var/lib/rancher/k3s/server/db
sudo sed -i.bak '/\/var\/lib\/rancher\/k3s\/server\/db/d' /etc/fstab
sudo umount /var/lib/rancher/k3s-ssd
sudo sed -i.bak '/\/var\/lib\/rancher\/k3s-ssd/d' /etc/fstab
sudo systemctl start k3s
```

如果 bind mount 尚未建立，第一条 `umount` 可以返回“not mounted”；必须核对 `/etc/fstab` 后再继续。

### K3s 已经在 SSD 上运行

机械盘原目录此时已经过期，不能直接重新暴露。先停止 K3s，把 SSD 上的最新数据复制回系统盘的同级暂存目录，再切换：

```bash
sudo systemctl stop k3s
sudo install -d -m 0700 /var/lib/rancher/k3s/server/db.rollback
sudo rsync -aHAX --numeric-ids --delete \
  /var/lib/rancher/k3s-ssd/db/ \
  /var/lib/rancher/k3s/server/db.rollback/
sudo umount /var/lib/rancher/k3s/server/db
rollback_stamp="$(date +%Y%m%d-%H%M%S)"
sudo mv /var/lib/rancher/k3s/server/db \
  "/var/lib/rancher/k3s/server/db.pre-ssd-${rollback_stamp}"
sudo mv /var/lib/rancher/k3s/server/db.rollback \
  /var/lib/rancher/k3s/server/db
sudo sed -i.bak '/\/var\/lib\/rancher\/k3s\/server\/db/d' /etc/fstab
sudo umount /var/lib/rancher/k3s-ssd
sudo sed -i.bak '/\/var\/lib\/rancher\/k3s-ssd/d' /etc/fstab
sudo systemctl start k3s
```

随后验证：

```bash
kubectl wait node/<节点名> --for=condition=Ready --timeout=300s
kubectl get --raw=/readyz?verbose | grep -F '[+]etcd ok'
```

如果最新数据无法安全复制回系统盘，停止操作，保留两边数据，转到 [K3s 恢复 Runbook](21-k3s-recovery.md) 使用迁移前 snapshot。不得直接执行 `cluster-reset`。

## 故障排查

- `missing command: ansible-config`：先把 `.private/ansible-venv/bin` 加入 `PATH`。
- `Use --limit with exactly one K3s node`：命令没有精确限制单个节点；不要放宽 playbook 断言。
- `Disk audit passed...allow_format=true`：这是预期停止点，不是故障；取得新的格式化确认后再执行。
- 候选盘数量不是 1：停止并重新核对 PVE 磁盘、来宾 `lsblk` 和容量，不要按 `/dev/sdb` 名称强行覆盖。
- snapshot、复制统计、bind mount、Node Ready 或 `[+]etcd ok` 任一失败：保持批次停止，先恢复当前节点。
- Terraform plan 验证失败：不得忽略或手工 apply；先解释 drift 或无关变更来源。

## 操作记录

每个停止点从 `templates/operation-log.md` 创建新的脱敏日志。记录分支、HEAD、目标 VM、保存 plan 的受保护路径及 SHA-256、候选盘稳定事实、退出码、验证和回滚结果。Token、state、kubeconfig、私钥和完整 plan JSON 只能留在 `.private/`。
