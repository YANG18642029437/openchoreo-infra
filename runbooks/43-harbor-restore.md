# Harbor PostgreSQL 恢复

先用匹配版本的 `pg_restore --list` 验证 custom-format dump。暂停 Harbor 写入，在空的
PostgreSQL 数据库中执行 `pg_restore --clean --if-exists`，随后验证 schema、项目和
artifact 元数据。数据库备份不包含 registry blobs；必须同时确认 NFS 上的 Harbor blob
目录存在且一致。Phase 05 验收仅做只读格式检查。
