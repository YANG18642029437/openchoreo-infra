# OpenChoreo Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 从当前 Proxmox 虚拟机状态出发，建设可由 Terraform、Ansible 和 Argo CD 重建并持续管理的三节点完整 OpenChoreo 平台。

**Architecture:** openchoreo-infra 管理 Proxmox、Ubuntu、K3s、Cilium、kube-vip、Argo CD 核心和恢复材料；openchoreo-gitops 管理 K3s 内所有平台组件和 OpenChoreo 声明。实施被拆成五份可独立验收的阶段计划，任何远程写操作都必须在代码验证、只读预检、备份验证和用户停止点之后执行。

**Tech Stack:** Proxmox VE、Ubuntu 24.04 Cloud Image、Terraform 1.15、bpg/proxmox、Cloud-Init、Ansible、K3s、Cilium、kube-vip、Argo CD、Kustomize、Helm、OpenChoreo、Harbor、OpenBao、ESO、Crossplane、CloudNativePG。

---

## 1. 为什么拆成五份计划

总设计包含仓库治理、虚拟化、Kubernetes 引导、GitOps 平台和端到端业务能力。将所有内容放进一个执行批次会导致：

- 无法在破坏性操作前形成清晰停止点。
- Terraform、Ansible 和 GitOps 的失败难以隔离。
- 两个仓库的提交无法独立审查。
- 平台安装失败时难以判断基础设施是否已经合格。

因此按以下顺序执行：

| 阶段 | 计划文件 | 可独立交付结果 |
|---|---|---|
| 1 | 2026-07-10-phase-01-repository-and-preflight.md | 仓库、安全边界、版本锁、只读审计 |
| 2 | 2026-07-10-phase-02-proxmox-terraform.md | Terraform/Cloud-Init、全量备份、四台 Ubuntu VM |
| 3 | 2026-07-10-phase-03-k3s-ansible.md | NFS、三节点 K3s、VIP、Cilium、Argo CD |
| 4 | 2026-07-10-phase-04-gitops-platform.md | MetalLB、DNS、TLS、存储、OpenBao、Harbor、四个 Plane |
| 5 | 2026-07-10-phase-05-crossplane-validation.md | Crossplane PostgreSQL、自助资源、发布、故障和恢复验收 |

每个阶段必须提交、推送并通过验收后才能开始下一阶段。

## 2. 统一版本矩阵

第一阶段将以下已核验版本写入 versions.lock.yaml。若执行日期晚于 2026-07-10，允许通过独立升级提案改变版本，但不得在实施过程中自动选择 latest。

| 组件 | 固定版本 |
|---|---|
| Terraform | 1.15.8 |
| bpg/proxmox | 0.111.1 |
| Ubuntu | 24.04 Noble Cloud Image |
| K3s | v1.35.6+k3s1 |
| Cilium | 1.19.5 |
| kube-vip | v1.2.1 |
| Argo CD Chart | 10.1.3 |
| Argo CD App | 3.4.5 |
| MetalLB Chart | 0.16.1 |
| ingress-nginx Chart | 4.15.1 |
| NFS CSI Driver | 4.13.4 |
| Gateway API | v1.4.1 |
| cert-manager | v1.19.4 |
| External Secrets Operator | 2.0.1 |
| kgateway | v2.2.1 |
| OpenBao Chart | 0.25.6 |
| OpenBao App | 2.4.4 |
| Harbor Chart | 1.19.1 |
| Harbor App | 2.15.2 |
| OpenChoreo | 1.1.2 |
| OpenChoreo logs module | 0.4.1 |
| OpenChoreo traces module | 0.4.1 |
| OpenChoreo metrics module | 0.6.1 |
| Crossplane | 2.3.3 |
| CloudNativePG | 1.30.0 |

OpenChoreo 的 cert-manager、ESO、kgateway、OpenBao 和 Observability 模块采用 v1.1.2 发布分支给出的兼容版本，不采用各项目更新但未经 OpenChoreo 组合验证的版本。

## 3. 两个实施 worktree

实施时分别创建：

    openchoreo-infra/.worktrees/codex/openchoreo-platform
    openchoreo-gitops/.worktrees/codex/openchoreo-platform

两个 worktree 使用同名分支 codex/openchoreo-platform。禁止直接在带有用户未跟踪文件的主工作区执行 git add -A。

## 4. 全局停止点

### 停止点 A：代码只读阶段完成

必须提供：

- 仓库契约测试通过。
- Terraform validate 通过。
- Ansible lint 和 syntax-check 通过。
- GitOps Kustomize/Helm 渲染通过。
- 敏感信息扫描通过。

此时没有远程写操作。

### 停止点 B：现场只读审计完成

必须提供：

- VM120、121、122 当前配置。
- 三块 200 GiB 盘的文件系统、挂载和数据检查。
- XJ6T 与备份存储剩余空间。
- VM ID 130 和模板 ID 9000 未占用。
- 192.168.2.170-179、183 无冲突。
- Terraform plan 文件和摘要。

### 停止点 C：全量备份完成

必须提供：

- VM120、121、122 的 vzdump 任务均为 TASK OK。
- 三个备份文件存在且非零。
- qmrestore dry-run 不可用时，至少验证 vzdump 日志、zstd 完整性和配置文件可读。
- 备份目标不与待删除 VM 磁盘共用同一个逻辑文件。

### 停止点 D：破坏性操作最终确认

用户必须在看到：

- 空盘证据。
- vzdump 证据。
- Terraform plan。
- 回滚命令。
- 预计中断范围。

之后明确确认，才允许删除旧 200 GiB 盘或原 VM。

### 停止点 E：K3s 基础验收

必须提供：

- 三节点 Ready。
- etcd 三成员健康。
- 192.168.2.179:6443 可用。
- Cilium status 通过。
- 任意单节点停机时 API 保持可用。

### 停止点 F：平台验收

必须提供：

- Argo CD Applications 全部 Synced/Healthy。
- OpenChoreo 四 Plane Ready。
- Harbor push/pull。
- OpenBao/ESO Secret 同步。
- Observability 查询。
- Crossplane PostgreSQL。
- Development 到 Production 提升。

## 5. 统一测试命令

在 openchoreo-infra worktree 运行：

~~~bash
./scripts/verify/repository.sh
./scripts/verify/terraform.sh
./scripts/verify/ansible.sh
./scripts/verify/secrets.sh
~~~

预期：每个命令输出 PASS 并返回 0。

在 openchoreo-gitops worktree 运行：

~~~bash
./scripts/verify/render.sh
./scripts/verify/policies.sh
./scripts/verify/secrets.sh
~~~

预期：所有 cluster overlay 成功渲染，不出现未固定 Chart 版本、明文 Secret 或 latest 镜像。

## 6. 全局提交策略

每个任务使用一个语义明确的提交。推荐提交顺序：

1. test: enforce infrastructure repository contract
2. docs: record approved infrastructure inventory
3. feat: add Proxmox Terraform modules
4. feat: add Ubuntu cloud image provisioning
5. feat: add Ansible host baseline
6. feat: bootstrap HA K3s with Cilium
7. feat: bootstrap Argo CD
8. feat: add Argo platform foundation
9. feat: deploy Harbor and secret management
10. feat: deploy OpenChoreo planes
11. feat: add Crossplane PostgreSQL API
12. test: add platform acceptance and recovery checks

不要把两个仓库放在同一个 Git 提交中。每个仓库独立提交、独立推送、独立验证。

## 7. 执行状态记录

每个远程阶段在 openchoreo-infra/logs 新建日期日志，至少记录：

- 执行人和时间。
- 变更前事实。
- 运行命令。
- 脱敏输出。
- 退出码。
- 验证证据。
- 回滚结果。
- 下一停止点。

日志禁止出现密码、Token、私钥、Kubeconfig 内容或 OpenBao 恢复密钥。

## 8. 完成定义

所有五份阶段计划完成，且设计文档第 21、22 节的验证和成功标准全部有当前证据后，才能把平台标记为完成。

仅完成 VM、仅完成 K3s、或仅显示 Pod Running 都不等于完成。

## 9. 设计覆盖矩阵

| 最终设计章节 | 实施任务 |
|---|---|
| 1–3 目标、非目标、虚拟机拓扑 | Phase 01 inventory/audit；Phase 02 Terraform VM |
| 4–5 网络、VIP、域名、TLS | Phase 03 kube-vip；Phase 04 Tasks 2–3 |
| 6–9 仓库边界、Terraform、Ansible、Argo CD | Phase 01–04 的仓库契约和唯一管理者 |
| 10 存储 | Phase 03 Task 3；Phase 04 Task 3；Phase 05 Task 5 |
| 11–14 OpenChoreo、Harbor、OpenBao、Crossplane | Phase 04 Tasks 4–5；Phase 05 Tasks 1–3 |
| 15–17 环境、登录、升级 | Phase 05 Tasks 3–4；固定版本矩阵；本地独立登录 |
| 18 备份与恢复 | Phase 02 Tasks 6–10；Phase 05 Tasks 5–6 |
| 19–20 仓库结构和实施阶段 | 五份阶段计划的文件结构与停止点 |
| 21–25 验证、成功标准、风险、决策、参考 | 每阶段完成条件；Phase 05 最终验收 |

覆盖矩阵只说明任务归属；最终是否完成必须以对应验证命令的当前输出为准。
