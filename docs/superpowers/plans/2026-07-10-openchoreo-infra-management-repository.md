# OpenChoreo 三节点基础设施管理仓库实施计划

> 已停止：本计划基于早期资源和 Flux 假设，已被 2026-07-10-openchoreo-platform-final-architecture-design.md 取代。不得执行本文件中的任务或命令；新实施计划必须在用户审阅新设计后重新编写。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `openchoreo-infra` 建设成三台 OpenChoreo 服务器的权威管理入口，并确保本地敏感信息不会进入 Git 或 GitHub。

**Architecture:** 仓库以 YAML 资产清单为机器可读事实源，以 Markdown 文档、Runbook 和追加式日志为人员操作入口，以 shell 验证脚本守住目录完整性和敏感信息边界。Terraform 负责基础设施与集群引导，Crossplane 负责集群内面向平台用户的资源供应；第一版只建立可执行骨架，不对远程 VM 做变更。

**Tech Stack:** Git、GitHub CLI、YAML、Markdown、Bash、Ansible、Terraform、K3s、OpenChoreo、Crossplane、gitleaks（可选增强检查）

---

## 文件结构与职责

本计划创建或修改以下文件：

- 根目录治理：`README.md`、`AGENTS.md`、`SECURITY.md`、`.gitignore`、`.gitleaks.toml`。
- 机器事实：`inventory/hosts.yaml`、`inventory/proxmox-pve2162.md`、三份 VM 记录。
- 架构与路线：`docs/architecture.md`、`docs/resource-plan.md`、`docs/deployment-roadmap.md`。
- 运行手册：`runbooks/00-preflight.md` 至 `runbooks/50-terraform.md`、`runbooks/backup-restore.md`。
- 操作证据：`logs/README.md`、`logs/2026-07-10-initial-audit.md`。
- 可复用脚本：`scripts/lib/common.sh`、`scripts/audit/remote-host.sh`、`scripts/verify/repository.sh`、`scripts/verify/test-repository.sh`、`scripts/bootstrap/README.md`。
- 自动化边界：`ansible/README.md`、`ansible/inventory/hosts.yml`、`ansible/group_vars/all.yml.example`、`ansible/playbooks/preflight.yml`、`terraform/README.md`、`terraform/backend.tf.example`、`gitops/README.md`。
- 操作模板：`templates/operation-log.md`、`templates/change-plan.md`、`templates/host-record.md`。
- 本机私有区：仅创建被忽略的 `.private/credentials/`、`.private/ssh/`、`.private/kubeconfigs/`、`.private/tokens/`、`.private/terraform-state/`，权限为 `0700`；第一版不写入聊天中出现过的真实密码。
- 父目录索引：`/Users/yangyongxiang/Desktop/code/github/AGENTS.md`、`/Users/yangyongxiang/Desktop/code/github/README.md`。

### Task 1: 先建立仓库结构与敏感信息契约测试

**Files:**
- Create: `scripts/verify/test-repository.sh`
- Create: `.gitignore`
- Create: `.gitleaks.toml`

- [ ] **Step 1: 写入会先失败的仓库契约测试**

创建 `scripts/verify/test-repository.sh`，检查根文件、目录、三台主机、Runbook、私有路径忽略规则和 Terraform state 忽略规则：

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

required_files=(
  README.md AGENTS.md SECURITY.md .gitignore .gitleaks.toml
  inventory/hosts.yaml inventory/proxmox-pve2162.md
  inventory/vm-120-yx2180.md inventory/vm-121-yx2181.md inventory/vm-122-yx2182.md
  docs/architecture.md docs/resource-plan.md docs/deployment-roadmap.md
  runbooks/00-preflight.md runbooks/10-ubuntu-install.md runbooks/20-k3s-ha.md
  runbooks/30-openchoreo.md runbooks/40-crossplane.md runbooks/50-terraform.md
  runbooks/backup-restore.md logs/README.md logs/2026-07-10-initial-audit.md
  scripts/lib/common.sh scripts/audit/remote-host.sh scripts/verify/repository.sh
  ansible/README.md ansible/inventory/hosts.yml ansible/group_vars/all.yml.example
  ansible/playbooks/preflight.yml terraform/README.md terraform/backend.tf.example
  gitops/README.md templates/operation-log.md templates/change-plan.md templates/host-record.md
)

for file in "${required_files[@]}"; do
  test -f "$file" || { printf 'missing required file: %s\n' "$file" >&2; exit 1; }
done

for host in 192.168.2.180 192.168.2.181 192.168.2.182; do
  grep -Fq "$host" inventory/hosts.yaml || { printf 'missing host: %s\n' "$host" >&2; exit 1; }
done

test_path=".private/credentials/ignore-test.txt"
tfstate_path="terraform/ignore-test.tfstate"
git check-ignore -q "$test_path"
git check-ignore -q "$tfstate_path"

if git ls-files | grep -E '(^|/)(\.private/|.*\.tfstate($|\.)|kubeconfig|.*\.(pem|key)$)' >/dev/null; then
  printf 'tracked sensitive path detected\n' >&2
  exit 1
fi

printf 'repository contract: PASS\n'
```

- [ ] **Step 2: 运行测试并确认它因文件缺失而失败**

Run:

```bash
chmod +x scripts/verify/test-repository.sh
./scripts/verify/test-repository.sh
```

Expected: 非零退出，并显示 `missing required file: README.md`。

- [ ] **Step 3: 写入敏感信息忽略规则**

创建 `.gitignore`：

```gitignore
.private/
*.pem
*.key
*.p12
*.kubeconfig
kubeconfig*
*.tfstate
*.tfstate.*
*.tfvars
!.tfvars.example
.env
.env.*
!.env.example
ansible/vault-password*
*.retry
.DS_Store
```

创建 `.gitleaks.toml`：

```toml
title = "openchoreo-infra secret scanning"

[extend]
useDefault = true

[allowlist]
description = "Allow documented non-secret private network addresses"
regexTarget = "match"
regexes = [
  '''192\.168\.2\.(162|180|181|182)'''
]
```

- [ ] **Step 4: 验证忽略规则已生效**

Run:

```bash
git check-ignore -v .private/credentials/ignore-test.txt terraform/ignore-test.tfstate kubeconfig-admin
```

Expected: 三个路径都匹配 `.gitignore` 中的规则。

- [ ] **Step 5: 提交测试与安全边界**

```bash
git add .gitignore .gitleaks.toml scripts/verify/test-repository.sh
git commit -m "test: enforce infrastructure repository contract"
```

### Task 2: 建立仓库入口、治理规则和安全说明

**Files:**
- Create: `README.md`
- Create: `AGENTS.md`
- Create: `SECURITY.md`

- [ ] **Step 1: 创建根 README 导航**

`README.md` 必须写明仓库职责、三台主机摘要、Terraform/Crossplane 分工、目录导航、标准操作流程、敏感信息存放方式和下一步顺序。导航至少链接到 `inventory/hosts.yaml`、三份架构文档、全部 Runbook、日志索引、Terraform、Ansible 和 GitOps 说明。

- [ ] **Step 2: 创建项目级 AGENTS 规则**

`AGENTS.md` 必须包含：文档使用中文；远程只读检查可直接进行；关机、重装、清盘、删资源、网络变更和 state 覆盖必须再次确认；所有变更写日志；禁止提交 `.private/` 和真实 secrets；资产变化同步 inventory。

- [ ] **Step 3: 创建安全处理说明**

`SECURITY.md` 必须定义敏感信息分类、本地目录权限、提交前检查、误提交响应流程。误提交响应顺序固定为：停止推送、轮换凭据、清理历史、重新扫描、记录事件。

- [ ] **Step 4: 运行契约测试确认仍只因后续文件缺失而失败**

Run:

```bash
./scripts/verify/test-repository.sh
```

Expected: 非零退出，首个缺失项进入 `inventory/`。

- [ ] **Step 5: 提交仓库入口文件**

```bash
git add README.md AGENTS.md SECURITY.md
git commit -m "docs: add repository governance and security guide"
```

### Task 3: 固化 Proxmox 与三台 VM 的事实清单

**Files:**
- Create: `inventory/hosts.yaml`
- Create: `inventory/proxmox-pve2162.md`
- Create: `inventory/vm-120-yx2180.md`
- Create: `inventory/vm-121-yx2181.md`
- Create: `inventory/vm-122-yx2182.md`

- [ ] **Step 1: 创建机器可读的主机清单**

`inventory/hosts.yaml` 使用以下稳定字段；不写密码：

```yaml
all:
  vars:
    ansible_user: root
    ansible_port: 22
    network_zone: lan-192.168.2.0-24
    proxmox_node: pve2162
  hosts:
    yx2180:
      ansible_host: 192.168.2.180
      vm_id: 120
      mac_address: BC:24:11:95:B9:86
      current_cpu: 4
      current_memory_gib: 16
      system_disk_gib: 100
      system_disk_storage: local
      planned_role: k3s-server-primary
    yx2181:
      ansible_host: 192.168.2.181
      vm_id: 121
      mac_address: BC:24:11:BB:7C:E3
      current_cpu: 4
      current_memory_gib: 16
      system_disk_gib: 100
      system_disk_storage: XJ6T
      planned_role: k3s-server-secondary
    yx2182:
      ansible_host: 192.168.2.182
      vm_id: 122
      mac_address: BC:24:11:B5:29:55
      current_cpu: 4
      current_memory_gib: 16
      system_disk_gib: 100
      system_disk_storage: XJ6T
      planned_role: k3s-server-secondary
```

- [ ] **Step 2: 创建 Proxmox 事实记录**

`inventory/proxmox-pve2162.md` 记录 PVE 8.2.2、56 CPU、251.54 GiB 内存、`local` 和 `XJ6T` 容量、三台 VM 位于同一物理宿主机，以及宿主机故障会同时影响三节点的风险。

- [ ] **Step 3: 创建三份 VM 记录**

每份 VM 文件记录 VM ID、IP、MAC、CPU、内存、系统盘、网桥 `vmbr0`、Proxmox firewall 标志、当前 CentOS 7 状态、规划角色、变更历史入口。VM121 和 VM122 的扩容目标分别记录为 6C/24GiB 与 8C/32GiB，但明确标为“待实施”，不能写成当前值。

- [ ] **Step 4: 验证三台主机均可被测试发现**

Run:

```bash
for ip in 192.168.2.180 192.168.2.181 192.168.2.182; do grep -F "$ip" inventory/hosts.yaml; done
```

Expected: 每个 IP 恰好输出一条主机地址记录。

- [ ] **Step 5: 提交资产清单**

```bash
git add inventory
git commit -m "docs: record three-node infrastructure inventory"
```

### Task 4: 编写架构、资源预算和部署路线

**Files:**
- Create: `docs/architecture.md`
- Create: `docs/resource-plan.md`
- Create: `docs/deployment-roadmap.md`

- [ ] **Step 1: 创建架构说明**

`docs/architecture.md` 必须包含下面的数据流和边界：

```text
Proxmox VM/网络/磁盘 -> Terraform
Ubuntu/K3s 基础配置 -> Ansible + Runbook
OpenChoreo 平台声明 -> openchoreo-gitops + Flux
开发者资源申请 -> OpenChoreo ResourceType -> Crossplane XR/MR
```

并明确 Terraform 不持续管理集群内业务资源，Crossplane 不负责重装三台 VM。

- [ ] **Step 2: 创建资源预算**

`docs/resource-plan.md` 记录当前 12C/48GiB 和拟调整后的 18C/72GiB；建议 VM120 4C/16GiB、VM121 6C/24GiB、VM122 8C/32GiB，每台增加 200GiB `XJ6T` 数据盘。文档注明最终配额需在 OpenChoreo 实测后再调优。

- [ ] **Step 3: 创建分阶段路线**

`docs/deployment-roadmap.md` 使用明确准入条件划分：仓库基线、PVE 变更、Ubuntu 24.04.4、K3s HA、OpenChoreo、Crossplane、Terraform 管理入口、备份恢复演练。每阶段只有当前阶段验证通过后才能进入下一阶段。

- [ ] **Step 4: 验证关键架构术语完整**

Run:

```bash
for term in Terraform Crossplane OpenChoreo K3s Proxmox; do rg -q "$term" docs; done
```

Expected: 命令退出码为 0。

- [ ] **Step 5: 提交架构文档**

```bash
git add docs/architecture.md docs/resource-plan.md docs/deployment-roadmap.md
git commit -m "docs: define platform architecture and rollout roadmap"
```

### Task 5: 建立分阶段 Runbook

**Files:**
- Create: `runbooks/00-preflight.md`
- Create: `runbooks/10-ubuntu-install.md`
- Create: `runbooks/20-k3s-ha.md`
- Create: `runbooks/30-openchoreo.md`
- Create: `runbooks/40-crossplane.md`
- Create: `runbooks/50-terraform.md`
- Create: `runbooks/backup-restore.md`

- [ ] **Step 1: 创建统一 Runbook 模板结构**

每份文件必须有且只使用以下一级章节：目标、适用范围、前置检查、操作步骤、预期结果、风险与影响、回滚、验证、操作日志。高风险步骤必须含 `停止点`，要求执行时再次获得用户确认。

- [ ] **Step 2: 写入预检和 Ubuntu 安装手册**

`00-preflight.md` 包含 SSH 连通性、时钟、磁盘、内存、网络、镜像仓库访问和 PVE 快照检查。`10-ubuntu-install.md` 固定目标镜像 `ubuntu-24.04.4-live-server-amd64.iso`，包含备份、关机、挂载 ISO、系统盘重装、cloud-init/手工安装选择、重建唯一 `machine-id`、验证 SSH 的步骤；实际关机前设置停止点。

- [ ] **Step 3: 写入 K3s 和 OpenChoreo 手册**

`20-k3s-ha.md` 采用三 server 嵌入式 etcd、固定 TLS SAN/入口地址、唯一 node name、禁用默认组件需显式记录的做法。`30-openchoreo.md` 包含版本锁定、依赖检查、命名空间、Helm/GitOps 安装入口、健康检查和失败回滚，不使用未经验证的 `latest`。

- [ ] **Step 4: 写入 Crossplane、Terraform 和备份恢复手册**

`40-crossplane.md` 说明 provider、ProviderConfig、XRD/Composition、OpenChoreo `ResourceType` 到 XR/MR 的映射与 ready/status/output 验证。`50-terraform.md` 说明 provider lock、plan 审核、state 位于 `.private/terraform-state/`、禁止本地和远端同时写 state。`backup-restore.md` 覆盖 PVE VM 备份、K3s etcd snapshot、Kubeconfig、GitOps 与 Terraform state 的恢复顺序。

- [ ] **Step 5: 验证每份 Runbook 的必需章节**

Run:

```bash
for file in runbooks/*.md; do
  for heading in '## 目标' '## 前置检查' '## 回滚' '## 验证'; do
    grep -Fq "$heading" "$file" || { printf '%s missing %s\n' "$file" "$heading"; exit 1; }
  done
done
```

Expected: 无输出且退出码为 0。

- [ ] **Step 6: 提交 Runbook**

```bash
git add runbooks
git commit -m "docs: add staged infrastructure runbooks"
```

### Task 6: 建立初始审计日志和可复用模板

**Files:**
- Create: `logs/README.md`
- Create: `logs/2026-07-10-initial-audit.md`
- Create: `templates/operation-log.md`
- Create: `templates/change-plan.md`
- Create: `templates/host-record.md`

- [ ] **Step 1: 创建追加式日志规则**

`logs/README.md` 定义文件名为 `YYYY-MM-DD-short-description.md`，禁止覆盖历史结论；纠错使用追加更正段。每条日志要记录范围、执行者、开始/结束时间、变更前状态、命令、脱敏输出、验证、回滚和后续动作。

- [ ] **Step 2: 记录 2026-07-10 初始审计**

初始日志记录三台 CentOS 7 主机的 4C/约15GiB/100GiB、无 swap、仅 22 端口、无容器与 Kubernetes 工具、NTP 同步、`machine-id` 重复、内网 RTT、镜像仓库可达，以及 Proxmox 存储和 VM 映射。明确本次仅只读，未修改远端配置。

- [ ] **Step 3: 创建变更计划、操作日志和主机记录模板**

模板使用 YAML front matter，字段固定为 `date`、`operator`、`scope`、`risk`、`status`；正文包含审批、备份、命令、验证证据、回滚结果。示例值只能是说明性文本，不能含真实密码、Token 或私钥。

- [ ] **Step 4: 检查日志中没有已知真实凭据模式**

Run:

```bash
rg -n '(password|passwd|token|secret|private key)[[:space:]]*[:=][[:space:]]*[^<[:space:]]+' logs templates && exit 1 || true
```

Expected: 无敏感赋值命中。

- [ ] **Step 5: 提交日志与模板**

```bash
git add logs templates
git commit -m "docs: add initial audit and operation templates"
```

### Task 7: 实现只读审计与仓库安全验证脚本

**Files:**
- Create: `scripts/lib/common.sh`
- Create: `scripts/audit/remote-host.sh`
- Create: `scripts/verify/repository.sh`
- Create: `scripts/bootstrap/README.md`

- [ ] **Step 1: 写公共 shell 函数**

`scripts/lib/common.sh` 提供 `die`、`require_command`、`repo_root` 三个函数，启用 `set -euo pipefail`，不读取或打印 `.private/` 内容。

- [ ] **Step 2: 写只读远端审计脚本**

`scripts/audit/remote-host.sh` 接受主机别名或 IP，通过 `ssh -o BatchMode=yes -o ConnectTimeout=5` 运行 `hostnamectl`、`uname -r`、`nproc`、`free -h`、`df -hT /`、`ip -brief address`、`ss -lnt`、`timedatectl show` 和容器工具存在性检查。脚本只打印事实，不运行安装、重启或写文件命令。

- [ ] **Step 3: 写完整仓库验证脚本**

`scripts/verify/repository.sh` 顺序执行：shell 语法检查、`test-repository.sh`、`git diff --check`、tracked 敏感路径检查、常见 secret 赋值扫描；如果本机安装 `gitleaks`，追加运行 `gitleaks git --no-banner --redact`。

- [ ] **Step 4: 给变更型脚本目录添加安全说明**

`scripts/bootstrap/README.md` 说明该目录未来脚本必须支持 `--check`、记录影响范围、验证前置条件、提供幂等性和对应 Runbook；第一版不提供会修改远端的脚本。

- [ ] **Step 5: 运行 shell 语法和仓库验证**

Run:

```bash
find scripts -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n
./scripts/verify/repository.sh
```

Expected: 输出 `repository contract: PASS` 和最终 `repository verification: PASS`。

- [ ] **Step 6: 提交脚本**

```bash
git add scripts
git commit -m "feat: add read-only audit and repository verification"
```

### Task 8: 建立 Ansible、Terraform 和 GitOps 边界骨架

**Files:**
- Create: `ansible/README.md`
- Create: `ansible/inventory/hosts.yml`
- Create: `ansible/group_vars/all.yml.example`
- Create: `ansible/playbooks/preflight.yml`
- Create: `terraform/README.md`
- Create: `terraform/backend.tf.example`
- Create: `gitops/README.md`

- [ ] **Step 1: 创建 Ansible 清单和只读预检 Playbook**

`ansible/inventory/hosts.yml` 引用三台 IP 与 `root` 用户，不包含密码。`preflight.yml` 使用 `gather_facts: true`、`changed_when: false` 输出发行版、内核、CPU、内存和根分区；`group_vars/all.yml.example` 只定义 SSH 端口、Python interpreter 等非敏感示例。

- [ ] **Step 2: 写 Ansible 使用边界**

`ansible/README.md` 说明第一次运行命令为：

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/preflight.yml --check
```

SSH 私钥从 `.private/ssh/` 通过命令行或本机 SSH config 引用，不能在 inventory 中保存密码。

- [ ] **Step 3: 写 Terraform state 边界和 backend 示例**

`terraform/README.md` 规定 Terraform 只管理 Proxmox VM、磁盘、网络和 Kubernetes bootstrap 接口；实际 state 使用 `-state=.private/terraform-state/proxmox.tfstate` 或受控远程 backend。`backend.tf.example` 使用 local backend 的相对路径 `../.private/terraform-state/proxmox.tfstate`，并说明复制后的真实 backend 文件也必须被忽略或不包含凭据。

- [ ] **Step 4: 写 GitOps 兄弟仓库接口**

`gitops/README.md` 链接 `https://github.com/YANG18642029437/openchoreo-gitops`，说明平台声明、Flux 同步与应用发布归 GitOps 仓库；本仓库只保存基础设施事实、Runbook 和外部依赖接口。

- [ ] **Step 5: 运行 YAML 基本解析或文本回退检查**

Run:

```bash
if command -v ruby >/dev/null; then
  ruby -e 'require "yaml"; ARGV.each { |f| YAML.load_file(f) }' inventory/hosts.yaml ansible/inventory/hosts.yml ansible/group_vars/all.yml.example ansible/playbooks/preflight.yml
else
  rg -q '^all:' inventory/hosts.yaml
fi
```

Expected: 无解析错误，退出码为 0。

- [ ] **Step 6: 提交自动化骨架**

```bash
git add ansible terraform gitops
git commit -m "feat: add infrastructure automation boundaries"
```

### Task 9: 创建本机私有区并验证权限与 Git 隔离

**Files:**
- Create locally, ignored: `.private/credentials/`
- Create locally, ignored: `.private/ssh/`
- Create locally, ignored: `.private/kubeconfigs/`
- Create locally, ignored: `.private/tokens/`
- Create locally, ignored: `.private/terraform-state/`

- [ ] **Step 1: 创建私有目录但不写入真实凭据**

Run:

```bash
install -d -m 700 .private .private/credentials .private/ssh .private/kubeconfigs .private/tokens .private/terraform-state
```

Expected: 命令成功且 Git 状态不显示这些目录。

- [ ] **Step 2: 验证目录权限**

Run:

```bash
find .private -type d -exec stat -f '%Sp %N' {} \;
```

Expected: 每行权限均以 `drwx------` 开头。

- [ ] **Step 3: 用无秘密测试文件验证普通 git add 不会纳入私有区**

Run:

```bash
touch .private/credentials/ignore-test.txt .private/terraform-state/ignore-test.tfstate
git add -A
git diff --cached --name-only | rg '^\.private/' && exit 1 || true
rm .private/credentials/ignore-test.txt .private/terraform-state/ignore-test.tfstate
```

Expected: 没有 `.private/` 路径进入暂存区。

- [ ] **Step 4: 清理仅为验证产生的暂存状态**

Run:

```bash
git restore --staged .
```

Expected: 只清除暂存标记，不改变工作区文件。

### Task 10: 更新父目录索引

**Files:**
- Modify: `/Users/yangyongxiang/Desktop/code/github/AGENTS.md`
- Modify: `/Users/yangyongxiang/Desktop/code/github/README.md`

- [ ] **Step 1: 在 AGENTS 目录记录中加入仓库名**

在 `openchoreo` 与 `openchoreo-gitops` 相邻位置增加：

```text
  - `openchoreo-infra`
```

- [ ] **Step 2: 在 README 当前内容中增加仓库说明**

增加：

```markdown
- `openchoreo-infra/`：OpenChoreo 三节点环境的基础设施管理仓库，用于维护 Proxmox/VM/K3s 资产清单、部署 Runbook、Terraform 与 Crossplane 分工、只读巡检脚本、操作日志和本地敏感信息隔离；私有远端为 `https://github.com/YANG18642029437/openchoreo-infra.git`。
```

- [ ] **Step 3: 验证两个父索引同时包含仓库名**

Run:

```bash
rg -n 'openchoreo-infra' /Users/yangyongxiang/Desktop/code/github/AGENTS.md /Users/yangyongxiang/Desktop/code/github/README.md
```

Expected: 两个文件各有至少一条命中。

### Task 11: 全量验证、提交并推送 GitHub

**Files:**
- Modify: `README.md`（仅在导航验证发现遗漏时）
- Modify: `docs/superpowers/plans/2026-07-10-openchoreo-infra-management-repository.md`（勾选已完成步骤）

- [ ] **Step 1: 运行全量仓库验证**

Run:

```bash
./scripts/verify/repository.sh
```

Expected: `repository contract: PASS` 与 `repository verification: PASS`。

- [ ] **Step 2: 验证 README 导航链接目标存在**

Run:

```bash
rg -o '\]\(([^)]+)\)' README.md | sed -E 's/^.*\]\(([^)]+)\)$/\1/' | while IFS= read -r target; do
  case "$target" in http://*|https://*) continue ;; esac
  test -e "$target" || { printf 'broken README link: %s\n' "$target"; exit 1; }
done
```

Expected: 无 broken link 输出。

- [ ] **Step 3: 检查 Git diff 和 tracked 敏感路径**

Run:

```bash
git diff --check
git status --short
git ls-files | rg '(^|/)(\.private/|.*\.tfstate($|\.)|kubeconfig|.*\.(pem|key)$)' && exit 1 || true
```

Expected: `git diff --check` 无输出；`git status` 只显示计划中的文档与脚本；敏感路径无命中。

- [ ] **Step 4: 验证 GitHub 仓库与可见性**

Run:

```bash
git remote -v
gh repo view YANG18642029437/openchoreo-infra --json nameWithOwner,visibility,url
```

Expected: `origin` 指向 `YANG18642029437/openchoreo-infra`，`visibility` 为 `PRIVATE`。

- [ ] **Step 5: 提交剩余仓库与父索引改动**

`openchoreo-infra` 仓库：

```bash
git add README.md AGENTS.md SECURITY.md inventory docs runbooks logs scripts ansible terraform gitops templates .gitignore .gitleaks.toml
git commit -m "docs: establish OpenChoreo infrastructure management baseline"
```

父目录不是独立 Git 仓库时，不创建额外提交；若父目录属于一个 Git 仓库，只提交两个索引文件，不包含其他现有改动。

- [ ] **Step 6: 推送 main 并复核远端**

Run:

```bash
git push origin main
git status --short --branch
gh repo view YANG18642029437/openchoreo-infra --json visibility,defaultBranchRef,url
```

Expected: `main...origin/main` 无 ahead/behind，工作区干净，远端为 `PRIVATE` 且默认分支为 `main`。

## 自审结果

- 设计规格第 5 至 7 节对应 Task 1、2、3、7、8、9。
- 架构、资源计划和阶段路线对应 Task 4。
- 全部七份 Runbook 对应 Task 5。
- 初始审计和追加式操作记录对应 Task 6。
- 父目录索引契约对应 Task 10。
- Git 忽略、tracked 文件扫描、可选 gitleaks、远端私有可见性和最终推送对应 Task 11。
- 远程 Ubuntu/K3s/OpenChoreo 实施明确排除在本计划之外，只生成后续实施所需的安全 Runbook。
