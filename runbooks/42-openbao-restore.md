# OpenBao Raft 恢复

先验证 `.snap` 的 gzip、`meta.json`、`state.bin` 和内部 SHA 清单。选择已解封的 active
OpenBao Pod，在维护窗口使用具备恢复权限的临时 token 执行
`bao operator raft snapshot restore <file>`。恢复后重新确认三成员 raft peer、seal 状态、
External Secrets 读取和 Harbor 登录。Phase 05 验收不执行此覆盖命令。
