# Agent Platform MinIO 凭据初始化记录

- 时间：2026-07-15 19:28:02 CST
- 操作者：Codex（经用户明确确认）
- 目标：homelab 集群 OpenBao 路径 `openchoreo/agent-platform/development/minio`
- 授权：用户在执行前确认写入 OpenBao 并继续 GitOps 发布
- 变更前事实：本地凭据文件已生成在受 Git 忽略的 `.private/openbao/agent-platform.env`，权限为 `0600`
- 运行命令：`./scripts/prepare/agent-platform-secrets.sh`、`./scripts/bootstrap/initialize-agent-platform-secrets.sh`
- 退出码：两个脚本均为 `0`
- 脱敏结果：OpenBao 幂等同步完成；`root_user` 为非空字符串，`root_password` 长度不少于 32 个字符
- 受保护原始证据路径：无；脚本不保存或输出 Secret 原始值
- SHA-256：不适用
- 验证：本地文件受 `.gitignore` 排除且权限为 `0600`；OpenBao 回读只通过 `jq -e` 验证字段类型和长度
- 回滚：通过 OpenBao 版本历史恢复该路径的上一版本；不得把历史值复制到 Git 或操作日志
- 下一停止点：推送两个 GitOps 相关仓库，等待 ResourceRelease 生成；尚未固定 ResourceReleaseBinding

本记录不包含用户名、密码、Token、Secret 数据或 kubeconfig 内容。
