# K3s etcd 恢复

仅在 API/etcd 已不可用且已获得覆盖恢复确认后执行。先验证 Mac 副本 SHA-256，停止三台
K3s server，把同一快照复制到首节点，使用
`k3s server --cluster-reset --cluster-reset-restore-path <snapshot>` 恢复首节点；确认 API
和 etcd 健康后，清理其余节点旧的 server DB 并按既有 token 逐台重新加入。不可同时在
多节点执行 cluster-reset。恢复前保留原数据目录的只读副本。
