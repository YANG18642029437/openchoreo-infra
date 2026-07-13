# 2026-07-13 Phase 04 Observability Plane 操作记录

## 基本信息

- 集群：`ocp-node-01`、`ocp-node-02`、`ocp-node-03`
- 命名空间：`openchoreo-observability-plane`
- 管理方式：Argo CD + Helm + OpenBao/External Secrets
- GitOps Revision：`18a196f`
- 状态：四个 Observability Application 均为 `Synced/Healthy`

## 部署组件

- OpenChoreo Observability Plane `1.1.2`
- Logs/OpenSearch 模块 `0.4.1`
- Tracing/OpenSearch 模块 `0.4.1`
- Metrics/Prometheus 模块 `0.6.1`
- 单节点 OpenSearch `3.3.0`，local-path `20Gi`
- Prometheus、Alertmanager、Prometheus Operator 与 kube-state-metrics，local-path `15Gi`
- Fluent Bit 三节点 DaemonSet、OpenTelemetry Collector
- Observer、Logs/Tracing/Metrics Adapter、Observability Cluster Agent
- kgateway HTTP 入口 `192.168.2.155`

## 执行结果

- OpenSearch 和 Observer 凭据通过 OpenBao 与 External Secrets 下发，Git 中无明文密码。
- 日志和链路保留期设置为 7 天，Prometheus 保留期设置为 15 天。
- OpenSearch 与 Prometheus 使用 local-path，避免数据库类负载落在 NFS。
- 修复 `nfs-shared` 与 `local-path` 同时为默认 StorageClass 的冲突；仅保留 local-path 为默认。
- Observer SQLite 的 `128Mi` PVC 已确认使用 local-path，WAL 初始化正常。
- Fluent Bit 内存上限调整为 `256Mi`，三节点采集 Pod 均 Ready。
- kube-state-metrics 存活探针提高 API 延迟容忍度，避免 embedded-etcd 慢盘期间误重启。
- `ClusterObservabilityPlane/default` 已注册，Agent 状态为 connected，连接数为 1。
- Gateway Service 获得 `192.168.2.155`，`observer.openchoreo.home.arpa/health` 返回 HTTP 200。

## 验证摘要

```text
Argo CD applications: 4 Synced, 4 Healthy
Non-job pods not ready: 0
OpenSearch PVC: 20Gi local-path
Prometheus PVC: 15Gi local-path
Observer SQLite PVC: 128Mi local-path
Observability Agent: connected, 1 agent
Gateway: 192.168.2.155
Observer health: HTTP 200
GitOps policy/secret checks: PASS
```

## 运行说明

- OpenSearch 是单节点模式。业务主分片均可用；出现副本分片无法分配导致的 `yellow` 不代表主分片不可用。
- 首次拉取和解压 OpenSearch、Prometheus、Envoy 镜像时三节点磁盘 I/O wait 明显升高，embedded-etcd API 会短时变慢；镜像缓存完成后无需重复下载。
- Mac 访问内部域名时需关闭会接管 `192.168.0.0/21` 的 Shadowrocket TUN 路由。
