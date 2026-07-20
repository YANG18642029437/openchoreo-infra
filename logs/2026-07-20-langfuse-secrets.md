# Agent Platform Langfuse 凭据初始化记录

- 时间：2026-07-20 14:20 CST
- 操作者：Codex（用户在当前任务中明确要求开始全量实施）
- 目标集群：OpenChoreo homelab
- 目标路径：`openchoreo/agent-platform/development/langfuse`、`openchoreo/agent-platform/development/redis`
- 本地入口：`.private/openbao/agent-platform.env`，权限验证为 `0600`
- 执行脚本：`scripts/prepare/agent-platform-secrets.sh`、`scripts/bootstrap/initialize-agent-platform-secrets.sh`
- 退出码：本地合同、准备和 OpenBao 幂等初始化均为 `0`
- Langfuse 字段：salt、encryption key、NextAuth、初始化管理员、Project API Key、PostgreSQL、Redis、MinIO、ClickHouse 字段均通过类型、前缀和长度校验
- Redis 隔离：业务默认密码保持独立，新增 `langfuse_password`；Langfuse 的 PostgreSQL/Redis URI 密码限定为 URL 安全的十六进制值
- 脱敏结果：终端只输出 PASS；OpenBao 回读只列出键名或执行 `jq -e` 验证，不输出任何值
- 受保护原始证据：真实值仅存在于 `.private/openbao/agent-platform.env` 与 OpenBao；kubeconfig、OpenBao Root Token 均继续位于 `.private/`
- 回滚：凭据路径可通过 OpenBao KV 版本历史恢复；恢复后必须让 ExternalSecret 同步并受控重启相应应用 Pod
- 后续动作：等待 GitHub 出口代理恢复后完成最终 Langfuse ResourceRelease 同步、真实 E2E 和权限负向验收

本文不包含密码、Token、API Key、kubeconfig 或 OpenBao Root Token 明文。
