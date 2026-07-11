# 基础设施代理规则

## 所有权与事实来源

- `inventory/hosts.yaml` 是唯一规范主机清单；禁止创建或维护重复的 Ansible inventory。
- `inventory/network.yaml` 与 `inventory/proxmox.yaml` 是期望状态来源。
- 期望状态不是已观测证据。实时预检只能产生证据和日志，不得自动改写清单。
- 集群内平台声明属于 `openchoreo-gitops`；本仓库负责基础设施和集群基础。

## 授权与停止点

任何删除、重装、关机、磁盘格式化、网络变更、`terraform apply` 和任何远程写操作，都必须在执行时获得新的明确确认；计划中的旧批准不能替代执行时确认。每次远程写操作都必须记录操作日志、验证和回滚结果。

## 敏感信息与证据

- 原始敏感证据、密码、令牌、密钥、kubeconfig、state 和备份只能放入 `.private/`。
- `logs/` 只允许脱敏日志；日志可引用受保护路径和校验和，不得复制原始秘密。
- 只读脚本必须保持 fail-closed。`NO_RESPONSE`、空输出、无签名或缓存缺失都不能单独证明资源不存在、空闲或可删除。

## Git 与工作区

- 禁止 `git add -A` 和 `git add .`；只显式暂存当前任务文件。
- 保留所有无关修改和未跟踪的用户内容，不得顺手整理。
- 禁止使用破坏性的 `git reset --hard` 或 `git checkout --` 清理工作区。
- 在任务分支和指定 worktree 中工作；开始前核对分支、HEAD 和干净状态，结束时再次核对。

## 验证要求

- 修改 shell 脚本后运行 Bash 3.2 兼容的 `bash -n` 和安全的本地桩测试。
- 不得为验证而擅自执行实时 SSH、ping、ARP、Terraform apply 或其他远程操作。
- 提交前运行 `./scripts/verify/secrets.sh`、`./scripts/verify/versions.sh`、`./scripts/verify/repository.sh` 和 `git diff --check`。
- 验证失败必须报告实际退出码和错误，不得把未知状态描述为成功。
