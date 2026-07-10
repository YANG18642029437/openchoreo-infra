# Phase 05 Crossplane, Release, and Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 提供由 Crossplane 与 CloudNativePG 实现的 PostgreSQL 自助资源，配置 Development→Staging→Production 发布路径，并完成平台、故障和恢复验收。

**Architecture:** Crossplane v2 只管理 Kubernetes 内的组合资源，不接管 Proxmox、K3s 或 NFS VM。一个 PostgreSQL XRD/Composition 生成 CloudNativePG Cluster、数据库凭据和连接 Secret；OpenChoreo ClusterResourceType 将开发者请求映射到该 XR。验收脚本从基础设施到应用发布逐层失败即停。

**Tech Stack:** Crossplane 2.3.3、CloudNativePG 1.30.0、OpenChoreo 1.1.2、Argo CD、Harbor、OpenBao/ESO、K3s embedded etcd。

---

## 文件结构

在 openchoreo-gitops 创建：

- clusters/homelab/applications/{14-crossplane.yaml,15-cloudnative-pg.yaml,16-platform-apis.yaml,17-environments.yaml}
- platform/crossplane/{kustomization.yaml,providers.yaml}
- platform/cloudnative-pg/{kustomization.yaml}
- platform/apis/postgresql/{definition.yaml,composition.yaml,functions.yaml,examples/development.yaml,examples/production.yaml}
- platform/openchoreo/resources/{cluster-resource-type-postgresql.yaml,environment-development.yaml,environment-staging.yaml,environment-production.yaml,release-pipeline.yaml}
- examples/smoke-app/{component.yaml,workload.yaml,api.yaml,build.yaml}
- scripts/verify/{crossplane.sh,openchoreo.sh,observability.sh,end-to-end.sh}

在 openchoreo-infra 创建：

- scripts/backup/{etcd-snapshot.sh,openbao-snapshot.sh,harbor-db.sh,pull-critical-backups.sh}
- scripts/verify/{backup-artifacts.sh,disaster-recovery.sh}
- runbooks/{40-platform-acceptance.md,41-backup-and-restore.md,42-single-node-failure.md}
- logs/acceptance/.gitkeep

## Task 1: 安装 Crossplane 和 CloudNativePG

**Files:**

- Create: clusters/homelab/applications/14-crossplane.yaml
- Create: clusters/homelab/applications/15-cloudnative-pg.yaml
- Create: platform/crossplane/{kustomization.yaml,providers.yaml}
- Create: platform/cloudnative-pg/kustomization.yaml

- [ ] **Step 1: 创建固定版本 Applications**

Crossplane Helm chart/app 固定 2.3.3，CloudNativePG 固定 1.30.0。Crossplane wave 50，CloudNativePG wave 50，平台 API wave 60。两个控制器都至少两副本并配置 pod anti-affinity。

- [ ] **Step 2: 写静态验证**

~~~bash
kustomize build platform/crossplane >/tmp/crossplane.yaml
kustomize build platform/cloudnative-pg >/tmp/cloudnative-pg.yaml
rg -n '2\.3\.3' clusters/homelab/applications/14-crossplane.yaml
rg -n '1\.30\.0' clusters/homelab/applications/15-cloudnative-pg.yaml
if rg -n 'proxmox|terraform' platform/crossplane; then
  printf 'phase 1 Crossplane scope violation\n' >&2
  exit 1
fi
~~~

Expected: 固定版本存在，未声明 Proxmox Provider。

- [ ] **Step 3: 同步并验证 CRD**

~~~bash
argocd app sync crossplane cloudnative-pg
kubectl wait --for=condition=Established crd/compositeresourcedefinitions.apiextensions.crossplane.io --timeout=5m
kubectl -n crossplane-system rollout status deployment/crossplane --timeout=10m
kubectl -n cnpg-system rollout status deployment/cnpg-controller-manager --timeout=10m
~~~

- [ ] **Step 4: 提交**

~~~bash
git add clusters/homelab/applications/{14-crossplane.yaml,15-cloudnative-pg.yaml} \
  platform/{crossplane,cloudnative-pg}
git commit -m "feat: install Crossplane and CloudNativePG"
~~~

## Task 2: 用契约测试定义 PostgreSQL 自助 API

**Files:**

- Create: platform/apis/postgresql/definition.yaml
- Create: platform/apis/postgresql/composition.yaml
- Create: platform/apis/postgresql/functions.yaml
- Create: platform/apis/postgresql/examples/{development.yaml,production.yaml}
- Create: scripts/verify/crossplane.sh

- [ ] **Step 1: 写会失败的 API 验证脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
required=(
  platform/apis/postgresql/definition.yaml
  platform/apis/postgresql/composition.yaml
  platform/apis/postgresql/examples/development.yaml
  platform/apis/postgresql/examples/production.yaml
)
for path in "${required[@]}"; do
  test -f "$path" || { printf 'missing PostgreSQL API file: %s\n' "$path" >&2; exit 1; }
done
kustomize build platform/apis/postgresql >/tmp/postgresql-api.yaml
kubectl apply --dry-run=server -f /tmp/postgresql-api.yaml >/dev/null
printf 'crossplane PostgreSQL API: PASS\n'
~~~

- [ ] **Step 2: 写 XRD schema**

API 为 database.openchoreo.io/v1alpha1、kind XPostgreSQL。spec.parameters 只暴露 environment、storageGiB、instances、databaseName；environment 枚举 development/staging/production，storageGiB 10–100，instances 1–3。status 暴露 ready、host、port、secretName。

- [ ] **Step 3: 写 Composition**

Composition 用 pipeline mode 和固定版本 function-patch-and-transform，生成：

- CloudNativePG Cluster；storageClass=local-path。
- bootstrap.initdb.database 来自 databaseName。
- development 默认 1 instance/10Gi；staging 2/20Gi；production 3/50Gi。
- managed roles/owner Secret 名称写入 XR status。
- connection Secret 只存在目标 namespace，不复制到 Git 或 Argo Application 参数。

- [ ] **Step 4: 写两个示例**

~~~yaml
apiVersion: database.openchoreo.io/v1alpha1
kind: XPostgreSQL
metadata:
  name: smoke-development
spec:
  parameters:
    environment: development
    databaseName: app
    instances: 1
    storageGiB: 10
~~~

production 示例必须 instances=3、storageGiB=50。

- [ ] **Step 5: 运行静态验证并提交**

~~~bash
./scripts/verify/crossplane.sh
git add platform/apis/postgresql scripts/verify/crossplane.sh
git commit -m "feat: add Crossplane PostgreSQL API"
~~~

## Task 3: 连接 OpenChoreo ClusterResourceType 和三环境

**Files:**

- Create: clusters/homelab/applications/16-platform-apis.yaml
- Create: clusters/homelab/applications/17-environments.yaml
- Create: platform/openchoreo/resources/cluster-resource-type-postgresql.yaml
- Create: platform/openchoreo/resources/environment-development.yaml
- Create: platform/openchoreo/resources/environment-staging.yaml
- Create: platform/openchoreo/resources/environment-production.yaml
- Create: platform/openchoreo/resources/release-pipeline.yaml

- [ ] **Step 1: 写 ClusterResourceType**

ClusterResourceType 把 PostgreSQL 请求映射为 XPostgreSQL，传递 environment、storageGiB、instances、databaseName，并把 status.host、status.port、status.secretName 作为工作负载绑定输出。不得在参数或 status 中返回密码。

- [ ] **Step 2: 写三个 Environment**

Development、Staging、Production 使用独立 namespace、ServiceAccount、ResourceQuota 和默认 NetworkPolicy。三者共享同一物理集群，但没有跨命名空间读 Secret 权限。

- [ ] **Step 3: 写 Release Pipeline**

顺序固定 Development→Staging→Production；Development 和 Staging 可由已批准 Git 提交自动推进；Production 必须 manual approval，且只允许提升同一镜像 digest，不重新构建。

- [ ] **Step 4: 服务端 dry-run 并提交**

~~~bash
kustomize build platform/openchoreo/resources >/tmp/openchoreo-resources.yaml
kubectl apply --dry-run=server -f /tmp/openchoreo-resources.yaml
git add clusters/homelab/applications/{16-platform-apis.yaml,17-environments.yaml} \
  platform/openchoreo/resources
git commit -m "feat: add OpenChoreo self-service environments"
~~~

Expected: 所有 OpenChoreo CR 被 API Server 接受。

## Task 4: 部署 smoke 应用并验证完整发布链

**Files:**

- Create: examples/smoke-app/{component.yaml,workload.yaml,api.yaml,build.yaml}
- Create: scripts/verify/openchoreo.sh
- Create: scripts/verify/observability.sh
- Create: scripts/verify/end-to-end.sh

- [ ] **Step 1: 定义最小应用**

smoke-app 提供 /healthz、/readyz、/api/db 三个端点；构建结果推送到 harbor.openchoreo.home.arpa/openchoreo/smoke-app，部署必须引用 sha256 digest。应用请求一个 development PostgreSQL 资源并只通过生成的 Secret 读取连接信息。

- [ ] **Step 2: 写 OpenChoreo 验证脚本**

脚本必须验证组件、工作负载、构建、部署轨迹；Harbor 存在对应 digest；Development 与 Staging 成功；Production 在批准前 Pending Approval，批准后运行同一 digest。

- [ ] **Step 3: 写 Observability 验证脚本**

对 smoke-app 发送 20 次 HTTP 请求，随后分别查询：

- Prometheus 中容器/HTTP 指标。
- OpenSearch 中 smoke-app 日志。
- tracing backend 中至少一条 smoke-app trace。
- Grafana datasource health。

每个查询必须返回可机器判断的非空结果，不能只检查 Pod Running。

- [ ] **Step 4: 写聚合验收脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail
scripts/verify/applications.sh
scripts/verify/crossplane.sh
scripts/verify/openchoreo.sh
scripts/verify/observability.sh
printf 'end-to-end platform validation: PASS\n'
~~~

- [ ] **Step 5: 执行、保存脱敏证据并提交**

~~~bash
./scripts/verify/end-to-end.sh | tee ../openchoreo-infra/logs/acceptance/$(date +%F)-platform.txt
git add examples/smoke-app scripts/verify/{openchoreo.sh,observability.sh,end-to-end.sh}
git commit -m "test: add OpenChoreo end-to-end acceptance"
~~~

Expected: 从构建、Harbor、数据库到三环境提升和观测查询全部 PASS。

## Task 5: 实施有限备份

**Files:**

- Create in infra: scripts/backup/etcd-snapshot.sh
- Create in infra: scripts/backup/openbao-snapshot.sh
- Create in infra: scripts/backup/harbor-db.sh
- Create in infra: scripts/backup/pull-critical-backups.sh
- Create in infra: scripts/verify/backup-artifacts.sh
- Create in infra: runbooks/41-backup-and-restore.md

- [ ] **Step 1: 配置 K3s etcd 快照**

三个 server 配置固定 schedule，每 6 小时快照、保留 56 份（14 天）。etcd-snapshot.sh 触发即时快照并复制最新文件到 192.168.2.183:/backups/etcd；文件名包含 UTC 时间和节点名。

- [ ] **Step 2: 配置 OpenBao Raft 快照**

openbao-snapshot.sh 使用最小权限 token 执行 operator raft snapshot save，写入 NFS backups/openbao；token 从 .private/openbao 或环境变量读取，脚本 stdout 不显示 token。

- [ ] **Step 3: 配置 Harbor 数据库备份**

harbor-db.sh 在 Harbor PostgreSQL Pod 内运行 pg_dump -Fc，将结果流式写入 NFS backups/harbor-db。Harbor registry blobs 已在 NFS，不重复复制到同一 NFS。

- [ ] **Step 4: 从 Mac 拉取关键快照**

pull-critical-backups.sh 只拉取最新 etcd、OpenBao、Harbor DB 到 openchoreo-infra/.private/backups/YYYY-MM-DD，并写 SHA-256 清单。明确记录：400 GiB NFS 数据没有异机全量备份，NFS VM/PVE 故障可能导致 Harbor blobs 与共享数据丢失。

- [ ] **Step 5: 验证并提交**

backup-artifacts.sh 必须验证三类备份都存在、非零、时间不超过 24 小时、sha256sum/shasum 校验通过。

~~~bash
./scripts/backup/etcd-snapshot.sh
./scripts/backup/openbao-snapshot.sh
./scripts/backup/harbor-db.sh
./scripts/backup/pull-critical-backups.sh
./scripts/verify/backup-artifacts.sh
git add scripts/backup scripts/verify/backup-artifacts.sh runbooks/41-backup-and-restore.md
git commit -m "feat: add critical platform backups"
~~~

## Task 6: 执行单节点故障和恢复验收

**Files:**

- Create in infra: scripts/verify/disaster-recovery.sh
- Create in infra: runbooks/40-platform-acceptance.md
- Create in infra: runbooks/42-single-node-failure.md

- [ ] **Step 1: 记录健康基线**

保存 nodes、etcd members、Cilium、Argo Applications、OpenChoreo Plane、Crossplane XR、CNPG Cluster、PVC 和 MetalLB Service 的脱敏输出。运行 backup-artifacts.sh，任何失败都停止演练。

- [ ] **Step 2: 停止一个非首节点**

只停止 k3s-02 或 k3s-03 的 k3s 服务。持续验证 192.168.2.179:6443、Argo CD、OpenChoreo control endpoint 和 smoke-app；预期业务仍可用，故障节点变 NotReady。

- [ ] **Step 3: 恢复节点**

启动 K3s 服务，等待节点 Ready、Cilium healthy、etcd member healthy、所有 Argo Application Synced/Healthy。若 15 分钟内未恢复，按 runbook 移除失效 etcd member 并重新加入节点。

- [ ] **Step 4: 做非破坏性恢复校验**

在隔离临时 namespace 创建新的 development XPostgreSQL，验证 Ready 和连接，再删除临时命名空间。对 etcd/OpenBao/Harbor backup 只做格式与可读性校验；实际覆盖恢复必须另行确认，不在生产式集群上直接执行。

- [ ] **Step 5: 运行最终验收**

~~~bash
../openchoreo-gitops/scripts/verify/end-to-end.sh
./scripts/verify/backup-artifacts.sh
./scripts/verify/disaster-recovery.sh
~~~

Expected: 全部 PASS，并在 logs/acceptance 留下时间、命令、退出码和脱敏输出。

- [ ] **Step 6: 提交**

~~~bash
git add scripts/verify/disaster-recovery.sh runbooks/40-platform-acceptance.md \
  runbooks/42-single-node-failure.md logs/acceptance/.gitkeep
git commit -m "test: add platform recovery acceptance"
~~~

## 最终完成条件

- Crossplane PostgreSQL API 可创建 development 与 production 配置，CNPG Ready。
- OpenChoreo Development→Staging→Production 使用同一镜像 digest，Production 有人工批准。
- metrics、logs、traces 三类查询都有真实 smoke-app 数据。
- 单个 K3s 节点停止时 API 和应用保持服务，恢复后集群重新 Healthy。
- etcd、OpenBao、Harbor DB 最近快照已拉到 Mac 且校验通过。
- 明确接受的剩余风险被写入验收报告：单 PVE 和 NFS VM 是 SPOF，400 GiB NFS 没有异机全量备份。
