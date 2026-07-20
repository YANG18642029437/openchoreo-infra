# Langfuse development 部署与验收记录

- 时间：2026-07-20 15:50 CST
- 操作者：Codex（用户要求全量执行 Langfuse 实施计划）
- 目标集群：OpenChoreo homelab
- 数据面 Namespace：`dp-agent-platfor-agent-platfor-development-4e4bdc7d`
- 受控入口：`https://192.168.2.154:31007`

## 实施结果

- Langfuse Web/Worker、ClickHouse 和 7 天清理任务均由 OpenChoreo ResourceType、Resource、ResourceReleaseBinding 管理。
- 最终固定发布：`langfuse-7449bfdb7d`、`clickhouse-6f6f6d8766`、`langfuse-retention-5d7498679b`、`redis-78bc6c7cb`。
- Web/Worker 均为单实例并 Ready；内外网 `health`、`ready` 均返回 `200`。
- 首次 423 条 Prisma 迁移已完成。Web 使用启动探针、单实例无并发迁移滚动策略、2 GiB 内存限额和 1.5 GiB Node.js 堆。
- PostgreSQL bootstrap revision 提升为 `v5`，MinIO bootstrap 保持 `v2`，避免无关任务重跑。
- ClickHouse ExternalSecret 使用显式 1 小时刷新；由于 OpenChoreo v1.1.2 会丢失部分 ExternalSecret 状态快照，最终 Binding 由 StatefulSet 登录探针验证 Secret 和凭据，状态为 `Ready=True`。

## 隔离与安全

- PostgreSQL：Langfuse role 无法读取 RAG `agent_platform` database 的知识库表。
- Redis：Langfuse ACL 用户可访问 DB 1；同一密码不能作为 default 用户登录 DB 0。
- MinIO：Langfuse 用户可访问自身事件 bucket，不能访问 `rag-documents`。
- 日志检查发现第三方启动日志曾输出含凭据的 Redis URI；凭据已立即轮换并同步 OpenBao、ExternalSecret 和 Redis ACL，旧值已失效。
- 新增 `ROTATE_LANGFUSE_REDIS_PASSWORD=1` 显式轮换入口及不泄露新旧值的自动测试。

## 出站恢复

- Argo CD Secret 同时维护大写和小写代理环境键，匹配 Deployment 的实际引用方式。
- repo-server 同时读取大小写代理变量，GitHub 经受控代理访问；验收时直连不可达、代理链路可达，因此不为公共域名设置 `NO_PROXY` 例外。
- `openchoreo-environments` 与 `agent-platform-control-plane` 最终均恢复 `Synced/Healthy`。

## 验收

- 真实 SDK 写入、Public API 异步查询、危险字段排除：通过。
- Langfuse Web/Worker 缩为 0 时，真实 SDK 和完整 Agent/ContextForge/RAG/前端 E2E 均通过；随后已恢复单实例。
- 7 天清理：8 天 Trace 被删除、6 天 Trace 保留；重复执行删除数为 0。
- GitOps foundation、IP access、render 和 retention 7 项单测：通过。

本文只保存脱敏结论，不包含密码、Token、API Key、kubeconfig、证书私钥或 OpenBao Root Token。
