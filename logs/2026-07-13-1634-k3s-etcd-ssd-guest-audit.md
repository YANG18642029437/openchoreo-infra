# 操作日志

- 时间：2026-07-13 16:34:56 CST
- 操作者：Codex（用户回复“继续”授权三台 VM 来宾只读审计）
- 目标：分别确认 VM120–122 能看到唯一的 19–21 GiB 空白非根数据盘，并停在格式化授权门禁。
- 授权：本次仅授权三台来宾实时只读磁盘审计；不包含格式化、创建文件系统、挂载、etcd snapshot、停止 K3s 或迁移数据。
- 变更前事实：Terraform apply 和 apply 后无 drift 验证已完成；三台 VM 的 Terraform state 均声明 `SSD1 / scsi1 / 20 GiB`。
- 运行命令：分别以 `--limit ocp-node-01`、`ocp-node-02`、`ocp-node-03` 运行 `ansible/playbooks/36-k3s-etcd-ssd.yml`，保持 `k3s_etcd_ssd_allow_format=false`。
- 退出码：三台 playbook 均按设计返回 2，原因均为显式格式化授权断言失败。
- 脱敏结果：三台节点均通过唯一 19–21 GiB 非根候选盘、空文件系统、空挂载点和非部分配置断言；每台 recap 均为 `changed=0`、`unreachable=0`，随后主动停止在格式化门禁。
- 受保护原始证据路径：`.private/evidence/2026-07-13-163345-ocp-node-01-k3s-etcd-ssd-audit.txt`、`.private/evidence/2026-07-13-163355-ocp-node-02-k3s-etcd-ssd-audit.txt`、`.private/evidence/2026-07-13-163406-ocp-node-03-k3s-etcd-ssd-audit.txt`。
- SHA-256：VM120 `bb69edb5b8e214996054a47ef6cfed6e2e395777adc83debfdc9fbf43f6dc09d`；VM121 `6ed1fadbbbe715b467f2101cf11305daa6125dbb1d4bfe67b122fd2e5d03236f`；VM122 `b7c10261a7e8e432ce2d39b30f6cb845308fad556584108aed434f44501f74ad`。
- 验证：所有审计证据都包含 `All assertions passed`、预期格式化停止消息、`changed=0` 和 `unreachable=0`。
- 回滚：审计没有执行来宾变更，无需回滚。
- 下一停止点：等待 VM120（`ocp-node-01`）格式化、etcd snapshot、停止 K3s、复制数据、bind mount 和健康恢复的新的明确确认。VM121、VM122 不包含在下一次确认中。

日志中未记录密码、令牌、私钥、kubeconfig 或完整块设备 JSON。
