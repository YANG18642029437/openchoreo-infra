# OpenChoreo Homelab 基础设施

本仓库 `openchoreo-infra` 管理 PVE、Terraform、Cloud-Init、Ubuntu、Ansible、K3s、kube-vip、Cilium、Argo CD 核心、NFS 和出站代理网关。集群内 OpenChoreo 平台资源由兄弟仓库 [openchoreo-gitops](https://github.com/YANG18642029437/openchoreo-gitops) 管理。

截至 2026-07-12，Phase 01、Phase 02 和 Phase 03 已完成。VM 120–122 运行三节点 K3s embedded etcd，API VIP 为 `192.168.2.179`，Cilium、kube-vip 和 Argo CD 核心已验证；VM130 提供 NFSv4。Phase 04 已创建 Root Application，但服务器访问 GitHub 超时；VM131 `egress-gateway-01` 已由 Terraform 创建并安装 sing-box，等待受保护的上游配置后启用。现场事实与故障恢复边界见 `logs/` 与 `runbooks/`。

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

## 实施入口

Terraform 已位于 `terraform/environments/homelab/` 和 `terraform/modules/`，其 Stop B 证据与后续停止点详见 [Phase 02 计划](docs/superpowers/plans/2026-07-10-phase-02-proxmox-terraform.md)。Ansible 将在 Phase 03 创建于 `ansible/`，并继续使用顶层主机清单，详见 [Phase 03 计划](docs/superpowers/plans/2026-07-10-phase-03-k3s-ansible.md)。集群内 GitOps 入口位于 [openchoreo-gitops](https://github.com/YANG18642029437/openchoreo-gitops)，边界见 [Phase 04 计划](docs/superpowers/plans/2026-07-10-phase-04-gitops-platform.md)。

关键运维 Runbook：

- [K3s etcd SSD 迁移与回滚](runbooks/23-k3s-etcd-ssd.md)
- [K3s 故障恢复](runbooks/21-k3s-recovery.md)
- [出站代理网关](runbooks/22-egress-gateway.md)

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

Agent Platform 的 MinIO、Redis 与 Langfuse 凭据使用以下本地入口维护：

```bash
./scripts/prepare/agent-platform-secrets.sh
./scripts/bootstrap/initialize-agent-platform-secrets.sh
```

真实值只保存在 `.private/openbao/agent-platform.env`，文件权限为 `0600`。初始化脚本把凭据同步到 OpenBao 的 `openchoreo/agent-platform/development/minio`、`redis`、`langfuse` 路径，终端只输出状态，不输出用户名、密码或 API Key。

若 Langfuse Redis 凭据需要应急轮换，使用 `ROTATE_LANGFUSE_REDIS_PASSWORD=1 ./scripts/prepare/agent-platform-secrets.sh`，随后执行 OpenBao 初始化脚本、等待 ExternalSecret 刷新并受控重启 Redis 与 Langfuse。development 最终部署与隔离验收见 [Langfuse development 部署记录](logs/2026-07-20-1550-langfuse-development-acceptance.md)。

## 当前执行顺序

Phase 04 正在 `codex/phase04-gitops` 分支实施。Root Application 已创建；当前停止点是为 VM131 注入受保护的 sing-box 上游配置并验证 GitHub、Helm 与镜像仓库出口。不要在本仓库的 Ansible role 中声明 OpenChoreo 平台应用。
