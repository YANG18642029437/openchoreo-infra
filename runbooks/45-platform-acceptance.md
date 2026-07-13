# Phase 05 平台验收

验收顺序：GitOps 静态契约、三环境同 digest 与数据库连接、metrics/logs/traces 查询、
三类备份可读性、单节点停止与恢复、隔离 PostgreSQL 创建/连接/清理。脱敏输出保存在
`logs/acceptance`；token、密码、kubeconfig、SSH key、备份正文始终只在 `.private`。

已接受剩余风险：单台 PVE 和 NFS VM 仍是 SPOF；400 GiB NFS 没有异机全量备份；
OpenChoreo 1.1.2 没有原生 Pending Approval 字段，production 以独立、带 approval
annotation 的 ReleaseBinding 创建动作记录显式批准。

## 延后处理决定

截至 2026-07-13，以下风险已知、已接受，作为个人实验环境暂不处理：

- 三台 K3s VM 共用单台 PVE 物理宿主机，暂不建设多物理机容灾。
- NFS 由单台 VM 提供，暂不建设双节点、高可用或自动故障切换。
- 400 GiB NFS 暂不执行异机全量备份；继续保留 etcd、OpenBao Raft 与 Harbor DB
  三类关键快照及 Mac 副本，但接受 Harbor blobs 和其他共享数据无法完整恢复的风险。
- OpenChoreo 1.1.2 暂时继续使用显式 ReleaseBinding annotation 记录 production 批准，
  暂不引入额外审批平台。

出现以下任一情况时重新评估：平台开始承载不可重建数据、供多人使用、需要长期稳定运行、
新增第二台物理服务器或 NAS、NFS 使用量明显增长，或一次故障恢复时间已不可接受。
