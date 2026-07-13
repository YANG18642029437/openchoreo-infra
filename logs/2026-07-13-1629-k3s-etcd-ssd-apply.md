# 操作日志

- 时间：2026-07-13 16:29:29 CST
- 操作者：Codex（用户在执行时明确确认 Terraform apply）
- 目标：应用已验证的保存 plan，为 VM120–122 各新增一块 `SSD1 / scsi1 / 20 GiB` 虚拟磁盘。
- 授权：用户回复“确认”，本次仅授权保存 plan 的 Terraform apply；不包含来宾 SSH 审计、格式化、停止 K3s 或数据迁移。
- 变更前事实：保存 plan SHA-256 为 `8b00d911e19587563513cb41c3aeb62cb6379d27b4518bb79a7a9e030023576c`；apply 前 JSON 门禁再次通过，Terraform 配置自 plan 生成后未变化。
- 运行命令：使用受保护 `TF_DATA_DIR`、provider cache 和环境文件执行保存 plan；随后读取 state 并运行 `terraform plan -detailed-exitcode`。
- 退出码：Terraform apply 为 0；state 磁盘检查为 0；apply 后 drift plan 为 0。
- 脱敏结果：`Apply complete! Resources: 0 added, 3 changed, 0 destroyed.` VM120、VM121、VM122 均存在 `SSD1 / scsi1 / 20 GiB`，`iothread=true`、`discard=on`、`ssd=true`。Apply 后 Terraform 返回 `No changes`。
- 受保护原始证据路径：`.private/evidence/2026-07-13-1628-k3s-etcd-ssd-apply.txt`、`.private/evidence/2026-07-13-1629-k3s-etcd-ssd-state-check.txt`、`.private/evidence/2026-07-13-1629-k3s-etcd-ssd-post-apply-plan.txt`。
- SHA-256：apply `f918ec5acdb86b12a9d8741953724b7966e356e03cf96182f97397fef67325a3`；state check `b879c1e66aae9e4620d5f210dd1598665ce4eba096c4a2b340dfa23723ba4eef`；post-apply plan `cb12757044264ed556a47f4d557fa84cd1de951a263c2bd8cea4ed155039bfc1`。
- 验证：Terraform state 磁盘检查 PASS；PVE refresh 后 drift plan 退出 0，真实基础设施与配置一致。
- 回滚：未执行。删除 `scsi1` 属于新的破坏性 Terraform 变更，必须先确认来宾未使用磁盘、生成新 plan 并取得新的删除确认。
- 下一停止点：等待新的来宾实时只读审计确认。审计只读取三台 VM 的 `findmnt` 和 `lsblk`，默认格式化开关保持关闭。

日志中未记录密码、令牌、私钥、kubeconfig、state 或完整 plan JSON。
