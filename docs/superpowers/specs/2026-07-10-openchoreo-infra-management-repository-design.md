# OpenChoreo 三节点基础设施管理仓库设计

日期：2026-07-10

> 历史方案：本文件已被 2026-07-10-openchoreo-platform-final-architecture-design.md 取代，仅用于保留早期仓库设计背景，不得继续作为实施依据。

## 1. 背景

当前 OpenChoreo 试运行环境由同一台 Proxmox VE 宿主机 `pve2162` 上的三台虚拟机组成：

| VM ID | 主机名 | IP | CPU | 内存 | 系统盘 |
|---|---|---|---:|---:|---:|
| 120 | `Yx2180` | `192.168.2.180` | 4 核 | 16 GiB | 100 GiB |
| 121 | `Yx2181` | `192.168.2.181` | 4 核 | 16 GiB | 100 GiB |
| 122 | `Yx2182` | `192.168.2.182` | 4 核 | 16 GiB | 100 GiB |

三台虚拟机将用于建设 K3s 三节点集群、完整 OpenChoreo 平面、Crossplane 资源供应能力和 Terraform 基础设施工作流。为了避免资产信息、部署步骤、可复用脚本和操作记录散落在聊天或 OpenChoreo 源码仓库中，需要建立独立的兄弟仓库 `openchoreo-infra`。

## 2. 目标

`openchoreo-infra` 是三台服务器的权威管理入口，负责：

1. 维护 Proxmox、虚拟机、网络、磁盘和 Kubernetes 资产清单。
2. 保存 Ubuntu、K3s、OpenChoreo、Crossplane 和 Terraform 的部署步骤。
3. 提供可重复执行的巡检、初始化、备份和恢复脚本。
4. 记录每一次远程操作的计划、命令、结果、验证和回滚方式。
5. 在本地安全保存运行所需的密码、SSH 私钥、Kubeconfig、Token 和 Terraform state。
6. 确保任何敏感信息都不会进入 Git 历史或 GitHub 私有仓库。
7. 与 `openchoreo` 源码仓库、`openchoreo-gitops` 声明仓库保持清晰边界。

## 3. 非目标

第一版不建设 Web 管理后台，不开发自定义 CMDB，不把 Proxmox、Kubernetes 和 GitHub 的所有操作封装成单一控制器，也不把现有 `openchoreo-gitops` 内容复制进来。

仓库只管理这套 OpenChoreo 三节点环境；其他不相关服务器继续由各自的管理目录负责。

## 4. 方案选择

比较三种方式：

1. 纯文档仓库：成本低，但无法稳定复用巡检、初始化和验证流程。
2. 文档、资产清单、Runbook、脚本和 IaC 骨架组合：既能立即使用，又能逐步自动化。
3. 第一版即实现完整 Terraform、Ansible 和 GitOps 自动化：初始复杂度过高，且服务器操作系统和磁盘布局仍在调整。

采用方案 2。仓库先形成可信的资产与操作基线，再按实际重复次数把成熟 Runbook 转换成 Ansible、Terraform 或脚本。

## 5. 仓库结构

```text
openchoreo-infra/
├── README.md
├── AGENTS.md
├── SECURITY.md
├── .gitignore
├── .gitleaks.toml
├── inventory/
│   ├── hosts.yaml
│   ├── proxmox-pve2162.md
│   ├── vm-120-yx2180.md
│   ├── vm-121-yx2181.md
│   └── vm-122-yx2182.md
├── docs/
│   ├── architecture.md
│   ├── resource-plan.md
│   ├── deployment-roadmap.md
│   └── superpowers/
│       ├── specs/
│       └── plans/
├── runbooks/
│   ├── 00-preflight.md
│   ├── 10-ubuntu-install.md
│   ├── 20-k3s-ha.md
│   ├── 30-openchoreo.md
│   ├── 40-crossplane.md
│   ├── 50-terraform.md
│   └── backup-restore.md
├── logs/
│   ├── README.md
│   └── 2026-07-10-initial-audit.md
├── scripts/
│   ├── audit/
│   ├── bootstrap/
│   ├── verify/
│   └── lib/
├── ansible/
│   ├── inventory/
│   ├── group_vars/
│   └── playbooks/
├── terraform/
│   └── README.md
├── gitops/
│   └── README.md
├── templates/
│   ├── operation-log.md
│   ├── change-plan.md
│   └── host-record.md
└── .private/                 # 仅本地存在，整个目录被 Git 忽略
    ├── credentials/
    ├── ssh/
    ├── kubeconfigs/
    ├── tokens/
    └── terraform-state/
```

## 6. 目录职责

### 6.1 `inventory/`

保存不敏感的事实数据，包括 VM ID、主机名、IP、MAC、CPU、内存、磁盘、Proxmox 存储池、操作系统、集群角色和当前状态。资产文件可以引用本地凭据的逻辑名称，但不能包含密码或私钥内容。

`hosts.yaml` 提供脚本和 Ansible 可消费的统一主机清单；Markdown 文件提供面向人的背景、历史和注意事项。

### 6.2 `docs/`

保存架构、资源预算和阶段性路线。架构文档必须明确：三台 VM 位于同一 Proxmox 宿主机，K3s 三节点只提供来宾系统和控制面进程级容错，不提供宿主机级高可用。

### 6.3 `runbooks/`

每个 Runbook 都必须包含：

1. 目标和适用范围。
2. 前置检查。
3. 明确命令。
4. 预期输出。
5. 风险和影响。
6. 回滚步骤。
7. 完成后的验证。

### 6.4 `logs/`

日志采用追加式记录。每次操作记录目标服务器、操作者、时间、变更前状态、执行命令、结果、验证证据和回滚结果。日志中出现敏感值时只能写经过脱敏的引用。

### 6.5 `scripts/`

脚本优先保持幂等和只读。会修改远程状态的脚本必须支持 `--check` 或等价的预检模式，并在文件头写明影响范围。

### 6.6 `ansible/`、`terraform/` 和 `gitops/`

- Ansible 管理来宾操作系统初始化和重复配置。
- Terraform 管理平台底座和未来可自动化的 Proxmox/云资源；state 只能写入本地 `.private/terraform-state/` 或受控远程 backend。
- `gitops/` 只记录与兄弟仓库 `openchoreo-gitops` 的接口、目录归属和同步规则，不复制 Flux 或 OpenChoreo 平台声明。

## 7. 敏感信息模型

敏感信息允许保存在本机，但必须满足以下约束：

1. 所有真实敏感文件统一放入 `.private/`，该目录权限设为 `0700`。
2. `.gitignore` 必须忽略 `.private/`、私钥、Kubeconfig、Token、环境变量、Terraform state 和非示例 `tfvars`。
3. 仓库只提交 `.example` 模板，不提交真实值。
4. 提交前运行敏感信息检查；初始实现使用模式扫描，并为 `gitleaks` 提供配置。
5. GitHub Actions 不读取本地 `.private/`，也不要求上传这些内容。
6. 如果敏感文件意外进入暂存区，提交必须失败；如果已经进入 Git 历史，立即停止推送并执行凭据轮换和历史清理。
7. 本地明文存储是第一版允许的最低标准，后续可将 `.private/` 升级为 SOPS + age 加密，但不能因此改变 Git 忽略边界。

需要忽略的主要模式：

```text
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
```

## 8. 操作流程

所有远程变更遵循统一生命周期：

```text
发现事实
  -> 编写变更计划
  -> 用户批准高风险操作
  -> 执行前备份或快照
  -> 执行变更
  -> 验证目标状态
  -> 写入操作日志
  -> 更新资产清单
```

关机、重装系统、清空磁盘、删除资源、修改网络和覆盖 Terraform state 属于高风险操作，必须在执行时再次确认。

## 9. 初始事实基线

初始审计应记录：

- 三台 VM 当前运行 CentOS Linux 7、内核 `3.10.0-1160.108.1.el7.x86_64`。
- 三台 VM 当前 `/etc/machine-id` 相同，需要在重装后验证唯一性。
- 三台 VM 内网 RTT 约为 0.15 至 0.4 毫秒。
- 当前仅 SSH 22 端口监听，未安装 K3s、Docker、containerd、Podman、kubectl 或 Helm。
- `XJ6T` 存储池约 5.95 TB，当前剩余约 2.98 TB。
- VM120 系统盘位于 `local`；VM121 和 VM122 系统盘位于 `XJ6T`。
- 三台 VM 的网络设备均连接 `vmbr0` 且启用了 Proxmox 防火墙标志。

## 10. GitHub 与索引

GitHub 仓库使用私有可见性：

```text
https://github.com/YANG18642029437/openchoreo-infra
```

首次发布后同步更新 `/Users/yangyongxiang/Desktop/code/github/AGENTS.md` 和 `/Users/yangyongxiang/Desktop/code/github/README.md`，使父目录能够发现新仓库及其职责。

## 11. 验证策略

仓库初始化完成后必须验证：

1. `git status` 只显示预期的可提交文件。
2. 在 `.private/` 创建测试敏感文件后，`git check-ignore` 能确认其被忽略。
3. `*.tfstate`、私钥、Kubeconfig 和非示例 `tfvars` 均不能进入暂存区。
4. 所有 inventory、runbook 和 log 入口都能从 `README.md` 导航。
5. 三台 VM 的 IP、VM ID、MAC 和存储池与现场检查一致。
6. GitHub 仓库可见性为 `PRIVATE`，远端只包含非敏感内容。
7. 父级 `AGENTS.md` 和 `README.md` 同时包含 `openchoreo-infra`。

## 12. 第一版交付范围

第一版创建完整目录、初始资产清单、初始审计日志、部署路线、Runbook 骨架、敏感信息忽略规则、提交前检查脚本、Ansible/Terraform/GitOps 边界说明和父目录索引。它不执行 Ubuntu 重装、K3s 安装或 OpenChoreo 部署；这些远程变更在仓库基线完成并审阅后按 Runbook 分阶段执行。

## 13. 验收标准

满足以下条件即认为仓库设计实现完成：

- 后续任务能够只从 `openchoreo-infra` 找到三台服务器的当前事实、下一步和历史操作。
- 敏感信息可以在本地安全区使用，但无法被普通 `git add .` 加入 Git。
- 每个远程操作都能对应到变更计划、执行日志和验证证据。
- OpenChoreo 源码、GitOps 声明和基础设施管理三类内容不互相混放。
- 私有 GitHub 仓库和本地父级索引均已建立。
