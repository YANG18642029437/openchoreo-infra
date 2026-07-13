# Phase 05 关键平台备份与恢复

本方案覆盖 K3s embedded etcd、OpenBao Raft 与 Harbor PostgreSQL。定时 etcd
快照保留 56 份（每 6 小时一份，共 14 天）；其余两类由脚本按需生成。三类产物先写入
`192.168.2.183:/srv/openchoreo/backups`，再把各自最新一份拉到 Mac 的
`.private/backups/YYYY-MM-DD` 并生成 SHA-256 清单。

## 生成与验证

```bash
scripts/bootstrap/initialize-backup-token.sh
scripts/backup/etcd-snapshot.sh
scripts/backup/openbao-snapshot.sh
scripts/backup/harbor-db.sh
scripts/backup/pull-critical-backups.sh
```

OpenBao token 仅有 `sys/storage/raft/snapshot` 的 read 权限，保存在被 Git 忽略的
`.private/openbao/backup.env`。任何日志和 Git 文件都不得包含 token、密码或快照内容。

## 恢复边界

- etcd：先停止全部 K3s server，选择一个快照执行 `k3s server --cluster-reset --cluster-reset-restore-path ...`，再依次重新加入其余 server。
- OpenBao：在已解封的 active Pod 使用 `bao operator raft snapshot restore`；覆盖恢复前必须再次获得明确确认。
- Harbor：在空的兼容 PostgreSQL 实例使用 `pg_restore --clean --if-exists`，并同时确认 registry blob 数据仍存在。

Phase 05 只验证产物非空、校验和与格式可读性，不执行覆盖恢复。

## 已接受风险

400 GiB NFS 数据目前没有异机全量备份。NFS VM 或单台 PVE 物理机故障，仍可能
同时影响 Harbor registry blobs 与 Kubernetes 共享数据；Mac 只保存三类关键控制面
快照，不等价于 NFS 的完整灾备副本。
