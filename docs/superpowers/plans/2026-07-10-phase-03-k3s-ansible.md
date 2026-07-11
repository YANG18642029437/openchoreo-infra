# Phase 03 K3s and Ansible Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 用 Ansible 将 VM130 配置为 NFSv4 服务器，并在 VM120–122 上构建带 kube-vip、Cilium 和 Argo CD 核心的三节点高可用 K3s 集群。

**Architecture:** Ansible 只管理操作系统基线、NFS、K3s、kube-vip、Cilium 和 Argo CD 核心。K3s 使用 embedded etcd，API VIP 为 192.168.2.179；集群内平台应用由下一阶段 Argo CD Root Application 接管。

**Tech Stack:** Ansible、Ubuntu 24.04、NFSv4、K3s v1.35.6+k3s1、kube-vip v1.2.1、Cilium 1.19.5、Helm、Argo CD Chart 10.1.3。

---

## 文件结构

- Create: ansible/ansible.cfg
- Create: ansible/requirements.yml
- Create: ansible/group_vars/all.yml
- Create: ansible/roles/common/{defaults/main.yml,tasks/main.yml,handlers/main.yml}
- Create: ansible/roles/nfs/{defaults/main.yml,tasks/main.yml,templates/exports.j2}
- Create: ansible/roles/k3s/{defaults/main.yml,tasks/main.yml,templates/config.yaml.j2}
- Create: ansible/roles/kube_vip/{defaults/main.yml,tasks/main.yml,templates/kube-vip.yaml.j2}
- Create: ansible/roles/cilium/{defaults/main.yml,tasks/main.yml}
- Create: ansible/roles/argocd/{defaults/main.yml,tasks/main.yml}
- Create: ansible/playbooks/{00-preflight.yml,10-common.yml,20-nfs.yml,30-k3s.yml,40-argocd.yml,site.yml}
- Create: scripts/verify/{ansible.sh,nfs.sh,cluster-foundation.sh}
- Create: scripts/bootstrap/export-kubeconfig.sh
- Create: runbooks/{20-ansible-bootstrap.md,21-k3s-recovery.md}

## Task 1: 定义 Ansible 静态契约

**Files:**

- Create: scripts/verify/ansible.sh
- Create: ansible/ansible.cfg
- Create: ansible/requirements.yml
- Create: ansible/group_vars/all.yml

- [ ] **Step 1: 写会失败的验证脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export ANSIBLE_CONFIG="$repo_root/ansible/ansible.cfg"
required=(
  ansible/ansible.cfg ansible/requirements.yml inventory/hosts.yaml
  ansible/group_vars/all.yml ansible/playbooks/00-preflight.yml
  ansible/playbooks/10-common.yml ansible/playbooks/20-nfs.yml
  ansible/playbooks/30-k3s.yml ansible/playbooks/40-argocd.yml ansible/playbooks/site.yml
)
for path in "${required[@]}"; do
  test -f "$path" || { printf 'missing Ansible file: %s\n' "$path" >&2; exit 1; }
done
ansible-config dump --only-changed | grep -F "$repo_root/ansible/roles"
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook -i inventory/hosts.yaml ansible/playbooks/site.yml --syntax-check
if command -v ansible-lint >/dev/null 2>&1; then ansible-lint ansible/; fi
printf 'ansible static validation: PASS\n'
~~~

- [ ] **Step 2: 运行并确认失败**

~~~bash
chmod +x scripts/verify/ansible.sh
./scripts/verify/ansible.sh
~~~

Expected: missing Ansible file: ansible/ansible.cfg。

- [ ] **Step 3: 写固定依赖和连接配置**

~~~ini
[defaults]
inventory = ../inventory/hosts.yaml
roles_path = roles
host_key_checking = True
interpreter_python = auto_silent
retry_files_enabled = False
stdout_callback = yaml

[ssh_connection]
pipelining = True
~~~

~~~yaml
collections:
  - { name: ansible.posix, version: "2.1.0" }
  - { name: community.general, version: "11.4.0" }
  - { name: kubernetes.core, version: "6.2.0" }
~~~

- [ ] **Step 4: 复用规范主机清单并写固定变量**

顶层 `inventory/hosts.yaml` 是唯一规范主机清单。Phase 3 不创建或维护第二份主机清单；继续使用规范别名 `ocp-node-01`、`ocp-node-02`、`ocp-node-03` 和 `nfs-storage-01`。

~~~yaml
ansible_ssh_private_key_file: "{{ lookup('env', 'OPENCHOREO_SSH_KEY') }}"
timezone: Asia/Shanghai
k3s_version: v1.35.6+k3s1
k3s_api_vip: 192.168.2.179
k3s_api_port: 6443
kube_vip_version: v1.2.1
cilium_version: 1.19.5
argocd_chart_version: 10.1.3
nfs_export_root: /srv/openchoreo
nfs_allowed_network: 192.168.2.0/24
~~~

- [ ] **Step 5: 提交契约**

~~~bash
git add ansible scripts/verify/ansible.sh
git commit -m "test: define Ansible bootstrap contract"
~~~

## Task 2: 建立 Ubuntu 基线和远程预检

**Files:**

- Create: ansible/playbooks/00-preflight.yml
- Create: ansible/playbooks/10-common.yml
- Create: ansible/roles/common/defaults/main.yml
- Create: ansible/roles/common/tasks/main.yml
- Create: ansible/roles/common/handlers/main.yml

- [ ] **Step 1: 写预检 Playbook**

~~~yaml
---
- name: Validate provisioned guests
  hosts: all
  gather_facts: true
  become: true
  tasks:
    - name: Require Ubuntu 24.04
      ansible.builtin.assert:
        that:
          - ansible_distribution == 'Ubuntu'
          - ansible_distribution_version is version('24.04', '==')
          - ansible_architecture == 'x86_64'
    - name: Require expected IPv4 address
      ansible.builtin.assert:
        that: ansible_host in ansible_all_ipv4_addresses
~~~

- [ ] **Step 2: 写 common role**

defaults/main.yml 固定安装 qemu-guest-agent、curl、ca-certificates、jq、nfs-common、open-iscsi、socat、conntrack、ethtool。tasks/main.yml 必须设置 inventory 主机名和 Asia/Shanghai，启用 qemu-guest-agent，关闭 swap，加载 overlay 与 br_netfilter，并持久化以下 sysctl：

~~~yaml
- { key: net.bridge.bridge-nf-call-iptables, value: '1' }
- { key: net.bridge.bridge-nf-call-ip6tables, value: '1' }
- { key: net.ipv4.ip_forward, value: '1' }
~~~

- [ ] **Step 3: 用 check mode 验证，再实际应用**

~~~bash
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
ansible-playbook -i inventory/hosts.yaml ansible/playbooks/00-preflight.yml
ansible-playbook -i inventory/hosts.yaml ansible/playbooks/10-common.yml --check --diff
ansible-playbook -i inventory/hosts.yaml ansible/playbooks/10-common.yml
ansible-playbook -i inventory/hosts.yaml ansible/playbooks/10-common.yml
~~~

Expected: 四台主机预检通过，第二次实际运行 changed=0。

实时预检只更新验证证据和日志，不自动改写表达期望状态的 `inventory/hosts.yaml`、`inventory/network.yaml` 或 `inventory/proxmox.yaml`。

- [ ] **Step 4: 提交**

~~~bash
git add ansible/roles/common ansible/playbooks/00-preflight.yml ansible/playbooks/10-common.yml
git commit -m "feat: add Ubuntu host baseline"
~~~

## Task 3: 配置 400 GiB NFSv4 数据盘

**Files:**

- Create: ansible/roles/nfs/defaults/main.yml
- Create: ansible/roles/nfs/tasks/main.yml
- Create: ansible/roles/nfs/templates/exports.j2
- Create: ansible/playbooks/20-nfs.yml
- Create: scripts/verify/nfs.sh

- [ ] **Step 1: 写磁盘安全断言**

使用 lsblk --json 选择唯一一个 390–410 GiB、TYPE=disk、无 mountpoint 的非系统盘。若候选不是恰好一个，或已有文件系统且 nfs_allow_format 未显式设为 true，立即失败。

~~~yaml
nfs_device: /dev/sdb
nfs_filesystem: xfs
nfs_allow_format: false
nfs_directories:
  - harbor/registry
  - shared
  - build-artifacts
  - backups/etcd
  - backups/openbao
  - backups/harbor-db
~~~

- [ ] **Step 2: 写 NFS role**

role 安装 nfs-kernel-server 与 xfsprogs，使用 community.general.filesystem 创建 XFS，以 UUID 挂载到 /srv/openchoreo，创建上述目录，并导出：

~~~text
/srv/openchoreo 192.168.2.0/24(rw,sync,no_subtree_check,root_squash,fsid=0,crossmnt)
~~~

格式化任务必须带 when: nfs_allow_format | bool；默认执行只审计，不格式化。

- [ ] **Step 3: 写验证脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail
: "${OPENCHOREO_SSH_KEY:?set OPENCHOREO_SSH_KEY}"
ssh -i "$OPENCHOREO_SSH_KEY" ubuntu@192.168.2.183 \
  'findmnt /srv/openchoreo && sudo exportfs -v && systemctl is-active nfs-server'
tmp="$(mktemp -d)"
trap 'sudo umount "'"$tmp"'" 2>/dev/null || true; rmdir "'"$tmp"'"' EXIT
sudo mount -t nfs4 192.168.2.183:/ "$tmp"
touch "$tmp/shared/.write-test"
rm "$tmp/shared/.write-test"
printf 'nfs validation: PASS\n'
~~~

- [ ] **Step 4: 在停止点 D 确认后应用并验证**

~~~bash
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
ansible-playbook -i inventory/hosts.yaml ansible/playbooks/20-nfs.yml -e nfs_allow_format=true
./scripts/verify/nfs.sh
~~~

Expected: XFS 挂载、NFSv4 导出和读写测试全部通过。

- [ ] **Step 5: 提交**

~~~bash
git add ansible/roles/nfs ansible/playbooks/20-nfs.yml scripts/verify/nfs.sh
git commit -m "feat: configure shared NFS storage"
~~~

## Task 4: 引导三节点 K3s、kube-vip 和 Cilium

**Files:**

- Create: ansible/roles/k3s/{defaults/main.yml,tasks/main.yml,templates/config.yaml.j2}
- Create: ansible/roles/kube_vip/{defaults/main.yml,tasks/main.yml,templates/kube-vip.yaml.j2}
- Create: ansible/roles/cilium/{defaults/main.yml,tasks/main.yml}
- Create: ansible/playbooks/30-k3s.yml
- Create: scripts/bootstrap/export-kubeconfig.sh
- Create: scripts/verify/cluster-foundation.sh

- [ ] **Step 1: 生成本地 K3s token**

~~~bash
install -d -m 0700 .private/tokens
umask 077
openssl rand -hex 32 > .private/tokens/k3s-server-token
~~~

Expected: 文件被 Git 忽略且权限为 0600。

- [ ] **Step 2: 写固定 K3s 配置模板**

~~~yaml
token: "{{ k3s_server_token }}"
node-ip: "{{ ansible_host }}"
advertise-address: "{{ ansible_host }}"
tls-san:
  - "192.168.2.179"
disable:
  - traefik
  - servicelb
flannel-backend: none
disable-network-policy: true
disable-cloud-controller: true
write-kubeconfig-mode: "0600"
{% if inventory_hostname != groups['k3s_servers'][0] %}
server: "https://192.168.2.179:6443"
{% endif %}
~~~

- [ ] **Step 3: 顺序安装 Server**

首节点先部署 kube-vip hostNetwork static pod，再以 INSTALL_K3S_VERSION=v1.35.6+k3s1 与 --cluster-init 安装。等待 VIP:6443 可用后，play 使用 serial: 1 顺序加入 ocp-node-02、ocp-node-03。Token 读取和模板任务必须 no_log: true。

- [ ] **Step 4: 安装 Cilium**

使用 Helm chart 1.19.5，固定 k8sServiceHost=192.168.2.179、k8sServicePort=6443、kubeProxyReplacement=false、operator.replicas=2、ipam.mode=kubernetes，然后执行 cilium status --wait。

- [ ] **Step 5: 导出管理员 kubeconfig**

~~~bash
#!/usr/bin/env bash
set -euo pipefail
: "${OPENCHOREO_SSH_KEY:?set OPENCHOREO_SSH_KEY}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
install -d -m 0700 "$repo_root/.private/kubeconfigs"
umask 077
ssh -i "$OPENCHOREO_SSH_KEY" ubuntu@192.168.2.180 \
  'sudo cat /etc/rancher/k3s/k3s.yaml' |
  sed 's#https://127.0.0.1:6443#https://192.168.2.179:6443#' \
  > "$repo_root/.private/kubeconfigs/homelab-admin.yaml"
KUBECONFIG="$repo_root/.private/kubeconfigs/homelab-admin.yaml" kubectl get nodes
~~~

- [ ] **Step 6: 写并运行基础验证**

cluster-foundation.sh 必须要求 Ready 节点数为 3，运行 k3s etcd-snapshot ls、cilium status、curl -k https://192.168.2.179:6443/livez，并断言 kube-system 中不存在 traefik 或 svclb Pod。

~~~bash
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
ansible-playbook -i inventory/hosts.yaml ansible/playbooks/30-k3s.yml
./scripts/bootstrap/export-kubeconfig.sh
./scripts/verify/cluster-foundation.sh
~~~

Expected: 三节点 Ready、VIP livez 成功、Cilium healthy。

- [ ] **Step 7: 提交**

~~~bash
git add ansible/roles/k3s ansible/roles/kube_vip ansible/roles/cilium \
  ansible/playbooks/30-k3s.yml scripts/bootstrap/export-kubeconfig.sh \
  scripts/verify/cluster-foundation.sh
git commit -m "feat: bootstrap HA K3s with Cilium"
~~~

## Task 5: 由 Ansible 引导 Argo CD 核心

**Files:**

- Create: ansible/roles/argocd/{defaults/main.yml,tasks/main.yml}
- Create: ansible/playbooks/40-argocd.yml
- Create: ansible/playbooks/site.yml
- Create: runbooks/20-ansible-bootstrap.md
- Create: runbooks/21-k3s-recovery.md

- [ ] **Step 1: 写 Argo CD role**

使用 kubernetes.core.helm 安装 argo/argo-cd Chart 10.1.3 到 argocd 命名空间，controller replicas=1、repoServer replicas=2、server replicas=2、applicationSet replicas=2、redis-ha enabled=true。Argo CD 核心不在 Root Application 中声明，避免自删除循环。

- [ ] **Step 2: 写 site.yml**

~~~yaml
---
- import_playbook: 00-preflight.yml
- import_playbook: 10-common.yml
- import_playbook: 20-nfs.yml
- import_playbook: 30-k3s.yml
- import_playbook: 40-argocd.yml
~~~

- [ ] **Step 3: 静态验证后安装**

~~~bash
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
./scripts/verify/ansible.sh
ansible-playbook -i inventory/hosts.yaml ansible/playbooks/40-argocd.yml
KUBECONFIG=.private/kubeconfigs/homelab-admin.yaml \
  kubectl -n argocd rollout status deployment/argocd-server --timeout=10m
~~~

Expected: Argo CD 控制器、repo server、server、ApplicationSet 和 Redis 全部 Ready。

- [ ] **Step 4: 做单节点故障验证**

集群健康且已创建 etcd snapshot 后，停止一台非首节点的 K3s 服务；验证 VIP livez、kubectl get nodes 与 Argo CD API 仍可用，然后立即恢复该节点。不得同时停止两台节点。

- [ ] **Step 5: 写恢复文档并提交**

文档必须包含 K3s token、kubeconfig 的本地位置，节点重新加入、etcd snapshot/restore、kube-vip/Cilium 恢复、Argo CD 重新引导及验证命令。

~~~bash
git add ansible/roles/argocd ansible/playbooks/40-argocd.yml ansible/playbooks/site.yml \
  runbooks/20-ansible-bootstrap.md runbooks/21-k3s-recovery.md
git commit -m "feat: bootstrap Argo CD core"
~~~

## 阶段完成条件

- scripts/verify/ansible.sh、nfs.sh、cluster-foundation.sh 均返回 0。
- 192.168.2.179:6443 从 Mac 可访问。
- 三个 embedded etcd 成员健康，单节点停止时 API 仍可用。
- NFSv4 根导出可读写，400 GiB 盘只挂载于 VM130。
- Argo CD 核心健康，但尚未创建平台 Root Application。
- 所有 Token、kubeconfig 和 SSH key 只存在 .private。
