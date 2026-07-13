# Phase 05 平台验收

验收顺序：GitOps 静态契约、三环境同 digest 与数据库连接、metrics/logs/traces 查询、
三类备份可读性、单节点停止与恢复、隔离 PostgreSQL 创建/连接/清理。脱敏输出保存在
`logs/acceptance`；token、密码、kubeconfig、SSH key、备份正文始终只在 `.private`。

已接受剩余风险：单台 PVE 和 NFS VM 仍是 SPOF；400 GiB NFS 没有异机全量备份；
OpenChoreo 1.1.2 没有原生 Pending Approval 字段，production 以独立、带 approval
annotation 的 ReleaseBinding 创建动作记录显式批准。
