# OpenChoreo Homelab 基础设施

本仓库 `openchoreo-infra` 管理 PVE、Terraform、Cloud-Init、Ubuntu、Ansible、K3s、kube-vip、Cilium、Argo CD 核心和 NFS。集群内 OpenChoreo 平台资源由兄弟仓库 [openchoreo-gitops](https://github.com/YANG18642029437/openchoreo-gitops) 管理。

截至 2026-07-11 本文更新时，当前只完成 Phase 01 的本地仓库、期望状态清单、验证器和只读审计脚本，尚未运行任何实时 PVE、网络或来宾审计；仓库内容不能当作已观测的现场事实。后续真实执行历史以 `logs/` 中的脱敏日志及其对受保护原始证据路径和校验和的引用为准。

## 设计与实施计划

- [最终架构设计](docs/superpowers/specs/2026-07-10-openchoreo-platform-final-architecture-design.md)
- [历史/已废弃：基础设施仓库设计](docs/superpowers/specs/2026-07-10-openchoreo-infra-management-repository-design.md)
- [总控实施计划](docs/superpowers/plans/2026-07-10-openchoreo-platform-implementation.md)
- [Phase 01：仓库与预检](docs/superpowers/plans/2026-07-10-phase-01-repository-and-preflight.md)
- [Phase 02：Proxmox 与 Terraform](docs/superpowers/plans/2026-07-10-phase-02-proxmox-terraform.md)
- [Phase 03：K3s 与 Ansible](docs/superpowers/plans/2026-07-10-phase-03-k3s-ansible.md)
- [Phase 04：GitOps 平台](docs/superpowers/plans/2026-07-10-phase-04-gitops-platform.md)
- [Phase 05：Crossplane 与验收](docs/superpowers/plans/2026-07-10-phase-05-crossplane-validation.md)

## 期望状态清单

- [主机清单](inventory/hosts.yaml)：唯一规范 Ansible 主机清单，不得复制到其他目录。
- [网络清单](inventory/network.yaml)：子网、VIP、MetalLB 池和服务地址。
- [Proxmox 清单](inventory/proxmox.yaml)：端点、模板和存储标识。

清单中的 `inventory_state: desired` 表示期望状态，`live_verification_required: true` 表示仍需实时只读核验。实时证据应写入受保护的证据目录和脱敏日志，不得自动覆盖期望值。

## 后续入口

Terraform 将在 Phase 02 创建于 `terraform/environments/homelab/` 和 `terraform/modules/`，详见 [Phase 02 计划](docs/superpowers/plans/2026-07-10-phase-02-proxmox-terraform.md)。Ansible 将在 Phase 03 创建于 `ansible/`，并继续使用顶层主机清单，详见 [Phase 03 计划](docs/superpowers/plans/2026-07-10-phase-03-k3s-ansible.md)。集群内 GitOps 入口位于 [openchoreo-gitops](https://github.com/YANG18642029437/openchoreo-gitops)，边界见 [Phase 04 计划](docs/superpowers/plans/2026-07-10-phase-04-gitops-platform.md)。

恢复 Runbook 计划由后续阶段创建在 `runbooks/`：PVE/Terraform 恢复见 [Phase 02](docs/superpowers/plans/2026-07-10-phase-02-proxmox-terraform.md)，K3s 恢复见 [Phase 03](docs/superpowers/plans/2026-07-10-phase-03-k3s-ansible.md)，最终恢复演练见 [Phase 05](docs/superpowers/plans/2026-07-10-phase-05-crossplane-validation.md)。

## 本地验证与审计

本地验证器：

- [Phase 01 规范本地门禁](scripts/verify/phase01.sh)
- [仓库契约](scripts/verify/repository.sh)
- [敏感信息边界](scripts/verify/secrets.sh)
- [版本锁定](scripts/verify/versions.sh)

只读审计脚本：

- [Proxmox 审计](scripts/audit/proxmox-readonly.sh)
- [IP 冲突审计](scripts/audit/ip-addresses.sh)
- [来宾磁盘审计](scripts/audit/guest-disks.sh)

当前只运行无连接的 dry-run：

```bash
IP_AUDIT_DRY_RUN=1 ./scripts/audit/ip-addresses.sh
GUEST_AUDIT_DRY_RUN=1 ./scripts/audit/guest-disks.sh
```

不要在尚未获得用户执行时确认前运行实时审计命令。IP 审计退出 `0` 表示未确认占用且无错误，`1` 表示确认占用，`2` 表示审计错误；来宾磁盘审计退出 `0` 表示全部主机审计成功，`2` 表示至少一个错误。`NO_RESPONSE`、空签名或缓存结果都不能单独证明资源空闲。

## `.private` 与操作记录

安全规则见 [SECURITY.md](SECURITY.md)。`.private/` 只允许保存本地凭据、SSH 密钥、kubeconfig、Terraform state、PKI、原始证据和备份；目录权限为 `0700`，文件为 `0600`，不得提交。任何文档或日志都不得包含密码、令牌、私钥或 kubeconfig 内容。严格敏感信息门禁：

```bash
REQUIRE_GITLEAKS=1 ./scripts/verify/secrets.sh
```

脱敏日志遵循 [日志规则](logs/README.md)，从 [操作日志模板](templates/operation-log.md) 开始。

## 当前执行顺序

截至 2026-07-11，Task 10／停止点 A 本地门禁已完成；当前保证等级为 `history=unscanned worktree-index-untracked=regex (REDUCED)`。下一步不是重复完成 Task 10，而是：

1. 获得用户新的明确批准后，执行实时只读审计并保存原始证据与脱敏日志。
2. 到达停止点 B，复核网络、PVE、磁盘和备份事实。
3. 再确认备份与回滚条件后，进入 Terraform 阶段。
