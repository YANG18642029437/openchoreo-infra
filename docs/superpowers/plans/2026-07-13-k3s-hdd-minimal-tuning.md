# K3s 机械盘最小优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不触碰 SSD、PVE 存储和 etcd 数据布局的前提下，逐台取消三台 K3s 节点根文件系统的持续 `discard`，保留每周 `fstrim`。

**Architecture:** 使用一个只作用于 `k3s_servers`、`serial: 1` 的独立 Ansible playbook 管理 `/etc/fstab`、即时 remount 和 `fstrim.timer`。使用本地静态契约门禁阻止范围扩大或引入磁盘破坏命令；远程执行前创建 etcd snapshot、核对 PVE 备份，并在每台变更后等待 Kubernetes Node Ready。

**Tech Stack:** Ansible、Bash 3.2、K3s、kubectl、Proxmox API、Git

---

## 文件结构

- Create: `scripts/verify/hdd-tuning.sh`：验证 playbook 范围、滚动策略、目标挂载参数、fstrim 和禁止命令。
- Create: `ansible/playbooks/35-k3s-hdd-tuning.yml`：逐台应用最小机械盘优化。
- Modify: `ansible/playbooks/site.yml`：把可重复执行的调优 playbook 纳入集群基线。
- Create: `logs/2026-07-13-k3s-hdd-minimal-tuning.md`：记录脱敏执行证据、结果和回滚状态。

### Task 1: 建立失败的本地契约门禁

**Files:**
- Create: `scripts/verify/hdd-tuning.sh`
- Test: `scripts/verify/hdd-tuning.sh`

- [ ] **Step 1: 写入静态契约验证器**

验证器必须检查：目标 playbook 存在；只使用 `k3s_servers`；包含 `serial: 1`、`any_errors_fatal: true`、`remount,nodiscard`、`fstrim.timer` 和 Node Ready 等待；不包含 `mkfs`、`wipefs`、`parted`、`fdisk`、`umount`、`terraform apply` 或 PVE 修改命令。

- [ ] **Step 2: 运行并确认 RED**

Run:

```bash
./scripts/verify/hdd-tuning.sh
```

Expected: FAIL，明确报告 `ansible/playbooks/35-k3s-hdd-tuning.yml` 尚不存在。

- [ ] **Step 3: 只提交测试**

```bash
git add scripts/verify/hdd-tuning.sh
git commit -m "test: define K3s HDD tuning contract"
```

### Task 2: 实现最小滚动调优

**Files:**
- Create: `ansible/playbooks/35-k3s-hdd-tuning.yml`
- Modify: `ansible/playbooks/site.yml`
- Test: `scripts/verify/hdd-tuning.sh`

- [ ] **Step 1: 创建滚动 playbook**

Playbook 的核心结构必须是：

```yaml
---
- name: Remove continuous discard from K3s nodes
  hosts: k3s_servers
  serial: 1
  any_errors_fatal: true
  gather_facts: false
  become: true
```

每台节点依次执行：验证唯一根挂载行、精确替换为 `defaults,commit=30,errors=remount-ro`、仅在修改时运行 `mount -o remount,nodiscard /`、启用并启动 `fstrim.timer`、验证 live mount 不包含 discard、从控制端执行 `kubectl wait node/<name> --for=condition=Ready --timeout=120s`。

- [ ] **Step 2: 将 playbook 纳入 site.yml**

在 `30-k3s.yml` 之后加入：

```yaml
- name: Apply minimal K3s HDD tuning
  import_playbook: 35-k3s-hdd-tuning.yml
```

- [ ] **Step 3: 运行 GREEN 门禁**

Run:

```bash
./scripts/verify/hdd-tuning.sh
bash -n scripts/verify/hdd-tuning.sh
OPENCHOREO_SSH_KEY=.private/ssh/openchoreo_ed25519 \
  KUBECONFIG=.private/kubeconfigs/homelab-admin-direct.yaml \
  .private/ansible-venv/bin/ansible-playbook \
  -i inventory/hosts.yaml ansible/playbooks/35-k3s-hdd-tuning.yml --syntax-check
```

Expected: 所有命令 PASS，不连接远程主机。

- [ ] **Step 4: 提交实现**

```bash
git add ansible/playbooks/35-k3s-hdd-tuning.yml ansible/playbooks/site.yml
git commit -m "feat: tune K3s nodes for HDD storage"
```

### Task 3: 建立远程执行停止点

**Files:**
- Read: `scripts/backup/proxmox-vms.sh`
- Read: `scripts/verify/proxmox-backups.sh`
- Read: `scripts/verify/cluster-foundation.sh`

- [ ] **Step 1: 确认本地和集群预检**

Run:

```bash
KUBECONFIG=.private/kubeconfigs/homelab-admin-direct.yaml kubectl get nodes
KUBECONFIG=.private/kubeconfigs/homelab-admin-direct.yaml kubectl get --raw=/readyz
```

Expected: 三台 Node Ready，`readyz` 返回 `ok`。

- [ ] **Step 2: 只读核对最近 PVE 备份证据**

Run:

```bash
source .private/terraform/proxmox.env
./scripts/verify/proxmox-backups.sh
```

Expected: VM 120、121、122 的最近全量备份验证通过。

- [ ] **Step 3: 展示远程写入命令并取得执行时确认**

待确认的远程写入只有：保存一次 etcd snapshot、备份和修改三台节点 `/etc/fstab`、执行根分区 remount、启用 `fstrim.timer`。没有格式化、卸载、删除、重启 VM 或停止 K3s。

### Task 4: 逐台应用并验证

**Files:**
- Execute: `ansible/playbooks/35-k3s-hdd-tuning.yml`
- Test: `scripts/verify/hdd-tuning.sh`

- [ ] **Step 1: 创建执行前 etcd snapshot**

Run:

```bash
ssh -i .private/ssh/openchoreo_ed25519 ubuntu@192.168.2.180 \
  'sudo k3s etcd-snapshot save --name pre-hdd-tuning-20260713'
```

Expected: snapshot save 成功，并能在 `sudo k3s etcd-snapshot ls` 中看到。

- [ ] **Step 2: 运行滚动 playbook**

Run:

```bash
OPENCHOREO_SSH_KEY=.private/ssh/openchoreo_ed25519 \
KUBECONFIG=.private/kubeconfigs/homelab-admin-direct.yaml \
.private/ansible-venv/bin/ansible-playbook \
  -i inventory/hosts.yaml ansible/playbooks/35-k3s-hdd-tuning.yml
```

Expected: 按 `ocp-node-01`、`ocp-node-02`、`ocp-node-03` 顺序成功；任一节点失败时停止。

- [ ] **Step 3: 验证三台节点实时状态**

对每台节点检查：

```bash
findmnt -rn -o OPTIONS /
systemctl is-enabled fstrim.timer
systemctl is-active fstrim.timer
grep '^LABEL=cloudimg-rootfs' /etc/fstab
```

Expected: mount 和 fstab 不包含 `discard`；timer 为 enabled、active。

- [ ] **Step 4: 验证 Kubernetes 与入口**

Run:

```bash
KUBECONFIG=.private/kubeconfigs/homelab-admin-direct.yaml kubectl get nodes
KUBECONFIG=.private/kubeconfigs/homelab-admin-direct.yaml kubectl get --raw=/readyz
```

并验证 Argo CD、Harbor、OpenBao、OpenChoreo Portal、Observer 返回 HTTP 200。

### Task 5: 记录、全量验证和交付

**Files:**
- Create: `logs/2026-07-13-k3s-hdd-minimal-tuning.md`

- [ ] **Step 1: 写脱敏操作日志**

记录开始和结束时间、snapshot 名、三台节点变更前后 mount 参数、timer 状态、Node 状态、入口验证和是否触发回滚；不得记录凭据内容。

- [ ] **Step 2: 运行提交前门禁**

Run:

```bash
./scripts/verify/hdd-tuning.sh
./scripts/verify/phase01.sh
git diff --check
git status --short
```

Expected: 全部 PASS，只有本任务日志尚未提交。

- [ ] **Step 3: 提交并推送**

```bash
git add logs/2026-07-13-k3s-hdd-minimal-tuning.md
git commit -m "docs: record K3s HDD tuning"
git push origin codex/phase04-gitops
```

Expected: 当前分支与远端同步，工作区无本任务残留。
