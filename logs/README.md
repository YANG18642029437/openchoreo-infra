# 脱敏操作日志

`logs/` 只保存可提交的脱敏操作记录。可能包含敏感信息的原始输出必须放入 `.private/evidence/`，备份放入 `.private/backups/`；目录权限必须为 `0700`，文件权限必须为 `0600`。

首次保存原始证据前，在仓库根目录执行：

```bash
install -d -m 0700 .private/evidence
umask 077
```

`.private/evidence/` 由仓库忽略规则排除，不得跟踪；上述 `umask` 确保随后创建的普通证据文件权限为 `0600`。

文件名使用 `YYYY-MM-DD-HHMM-<operation>.md`。每次操作从 `templates/operation-log.md` 开始，记录命令退出码、脱敏证据、原始证据校验和、验证结果和下一停止点。

永远不要覆盖旧日志；创建新的时间戳文件。日志不得包含密码、令牌、密钥、kubeconfig、state 内容或其他秘密。

## Agent Platform 记录

- `2026-07-15-agent-platform-secrets.md`：记录 development 环境 MinIO 凭据的本地准备、OpenBao 幂等同步和脱敏验证结果；后续在同一文件追加 ResourceReleaseBinding 最终验收。
- `2026-07-20-langfuse-secrets.md`：记录 development 环境 Langfuse/Redis 独立凭据的本地准备、OpenBao 幂等同步和脱敏验证结果。
