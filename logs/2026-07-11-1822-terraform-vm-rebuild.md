---
date: 2026-07-11
operator: Codex with user approval
scope: PVE VM 120, 121, 122 and 130 Terraform rebuild
risk: high
status: completed
---

# Phase 02 Terraform VM 重建

## 审批与安全边界

- 用户明确确认使用 Ubuntu Cloud Image 模板和 Terraform 重建虚拟机。
- 用户明确确认临时开启 `terraform@pve` 根 ACL 传播；实时权限验证不满足条件后，没有在该权限窗口执行 Terraform apply，并立即把根 ACL 恢复为 `propagate=0`。
- 最终创建使用既有角色在精确本地网桥权限路径上的授权完成，没有长期扩大根权限。
- VM 120、121、122 的既有全量备份继续保留在 `PvEDump`，本次没有删除备份。

## 执行结果

| VM ID | 名称 | 地址 | CPU / 内存 | 磁盘 | 状态 |
|---:|---|---|---|---|---|
| 120 | `ocp-node-01` | `192.168.2.180/21` | 4 核 / 16 GiB | 100 GiB | running，SSH 已验证 |
| 121 | `ocp-node-02` | `192.168.2.181/21` | 4 核 / 16 GiB | 100 GiB | running，SSH 已验证 |
| 122 | `ocp-node-03` | `192.168.2.182/21` | 4 核 / 16 GiB | 100 GiB | running，SSH 已验证 |
| 130 | `nfs-storage-01` | `192.168.2.183/21` | 2 核 / 4 GiB | 32 GiB + 400 GiB | running，SSH 已验证 |

基础模板为 VM 9000 `ubuntu-2404-cloud-template`，保持 stopped/template 状态并归属 `openchoreo` 资源池。

## Terraform 收敛处理

- 首次创建已在 PVE 成功，但 Provider 等待未运行的 QEMU Guest Agent，导致状态长时间停留在 creating。
- 四台主机的静态 IP 和 SSH 均已验证，因此模块明确设置 `agent.enabled=false`，不再把 Guest Agent 作为就绪信号。
- 后续原地更新完成系统盘扩容并写入完整 state：`0 added, 4 changed, 0 destroyed`。
- 最终刷新计划结果为 `No changes`；state 包含四个 VM 资源。
- 静态校验脚本、`terraform fmt -check` 和 `terraform validate` 均通过。

## 最终安全核验

- PVE 根 ACL：`terraform@pve / OpenChoreoTerraform / propagate=0`。
- VM 120、121、122 系统块设备均为 100 GiB。
- VM 130 系统块设备为 32 GiB，数据块设备为 400 GiB。
- `.private/` 内的 Terraform state、plan、凭据和 SSH 私钥仍由忽略规则排除，未写入本日志。

## 下一停止点

下一阶段是通过 Ansible 配置 VM 130 的 NFSv4 服务并在三台 K3s 节点上安装 K3s。该阶段会修改来宾操作系统，执行前应先确认 Ansible inventory、磁盘设备映射和 NFS 导出路径。
