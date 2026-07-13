# 单 K3s 节点故障演练

运行前必须通过 `scripts/verify/backup-artifacts.sh`。执行：

```bash
DRILL_MODE=execute scripts/verify/disaster-recovery.sh
```

默认目标是 `ocp-node-03`。脚本只停止该节点的 K3s 服务，验证 VIP API 与三个 smoke
端点持续可用，然后启动服务并等待 Node Ready、Cilium 和端到端验收。EXIT trap 会在
任何错误时尝试恢复服务。若 10 分钟仍未 Ready，停止自动操作，检查 systemd 日志、
Cilium 与 etcd 状态；未经再次确认不得移除 etcd member。
