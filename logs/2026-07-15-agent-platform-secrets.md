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
- 下一停止点：已完成 GitOps 发布和集群验收；后续进入 Agent Platform 应用层本地开发

本记录不包含用户名、密码、Token、Secret 数据或 kubeconfig 内容。

## development 基础资源验收

- 时间：2026-07-15 20:33:50 CST
- GitOps 状态：`homelab-root`、`openchoreo-environments`、`agent-platform-control-plane`、`rabbitmq-cluster-operator`、`milvus-operator` 均为 `Synced/Healthy`
- OpenChoreo Binding：`minio-development`、`rabbitmq-development`、`milvus-development` 均为 `Ready=True`
- 固定 Release：MinIO `minio-5758654ffc`、RabbitMQ `rabbitmq-5f96bbf5dc`、Milvus `milvus-c84654c84`
- MinIO：单副本 Pod Ready，`20Gi` PVC 为 `Bound`，确认存在 `milvus` 与 `knowledge-base` Bucket
- RabbitMQ：单副本 Pod Ready，`10Gi` PVC 为 `Bound`，`AllReplicasReady=True`、`ClusterAvailable=True`，默认用户 Secret 仅验证存在
- Milvus：standalone Pod Ready、重启次数为 `0`，镜像 `milvusdb/milvus:v2.6.16`，状态为 `Healthy`，etcd 与 RocksMQ 的 `10Gi` PVC 均为 `Bound`
- 故障修正：显式设置 Milvus `MINIO_PORT=9000`，避免 Kubernetes Service Links 注入的 `tcp://` 值覆盖 Milvus 配置
- 验证：`scripts/verify/agent-platform-foundation.sh` 通过；验收输出只记录资源名称、状态、容量和非敏感 endpoint

本节未读取或记录 MinIO、RabbitMQ、OpenBao 的 Secret 明文。
