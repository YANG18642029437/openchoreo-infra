---
date: 2026-07-11
operator: Codex with user approval
scope: PVE VM 120, 121, 122 snapshot backups
risk: medium
status: completed
---

# Phase 02 vzdump 全量备份

## 审批与边界

- 用户明确确认执行三台 VM 全量备份。
- 使用 PVE API 串行执行 snapshot 模式 vzdump，没有通过 SSH 登录 PVE。
- 未停止、删除或修改 VM；未执行 Terraform apply。
- 备份目标固定为 VM 120、121、122，存储为 `PvEDump`。

## 执行结果

| VM ID | 任务结果 | 压缩备份大小 |
|---:|---|---:|
| 120 | `BACKUP_OK` | 3.25 GiB |
| 121 | `BACKUP_OK` | 3.02 GiB |
| 122 | `BACKUP_OK` | 1.09 GiB |

执行完成后 `PvEDump` 可用容量约 9050.2 GiB。三个任务串行运行，避免并发备份造成额外磁盘压力。

## 受保护证据

- 唯一运行 manifest 保存在 `.private/backups/`，权限为 `0600`。
- manifest SHA-256：`0a40d833917257c2220277a7e59972c0de95c6f4aa1d3b19a82f877a67726164`。
- 独立验证结果保存在 `.private/backups/vzdump-verification.txt`，权限为 `0600`。
- 验证结果 SHA-256：`d45e75ab60a7baaf79e3b488edf132db3a11f5036b4189e9c2dc83dd2443b58d`。
- 仓库日志不记录 API 凭据、UPID 或受保护文件内容。

## 下一停止点

备份条件已经满足，但删除 VM 120–122 和执行 Terraform apply 仍属于独立的不可逆停止点。执行前必须重新展示本日志、唯一 manifest 验证、Terraform plan 和恢复方式，并取得用户明确确认。
