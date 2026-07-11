# 脱敏操作日志

`logs/` 只保存可提交的脱敏操作记录。可能包含敏感信息的原始输出必须放入 `.private/evidence/`，备份放入 `.private/backups/`；目录权限必须为 `0700`，文件权限必须为 `0600`。

文件名使用 `YYYY-MM-DD-HHMM-<operation>.md`。每次操作从 `templates/operation-log.md` 开始，记录命令退出码、脱敏证据、原始证据校验和、验证结果和下一停止点。

永远不要覆盖旧日志；创建新的时间戳文件。日志不得包含密码、令牌、密钥、kubeconfig、state 内容或其他秘密。
