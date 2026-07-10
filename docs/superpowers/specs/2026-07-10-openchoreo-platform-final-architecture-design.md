# OpenChoreo 三节点平台最终架构设计

日期：2026-07-10

状态：待用户书面审阅

本设计取代同目录中的 2026-07-10-openchoreo-infra-management-repository-design.md，以及 plans 目录中的 2026-07-10-openchoreo-infra-management-repository.md。旧文件保留为历史记录，不得继续作为实施依据。

## 1. 目标

在一台 Proxmox VE 物理宿主机上，使用四台 Ubuntu 虚拟机建设一套可重复创建、可通过 Git 持续管理、可从源代码构建应用并完成三阶段发布的 OpenChoreo 内网平台。

最终平台必须具备：

1. 三节点 K3s Server 和 embedded etcd。
2. kube-vip 提供稳定的 Kubernetes API VIP。
3. Cilium 提供 Pod 网络和 OpenChoreo Cell 网络隔离。
4. Argo CD 持续管理集群内平台组件。
5. OpenChoreo Control、Data、Workflow、Observability 四个 Plane。
6. Harbor 私有镜像仓库。
7. OpenBao 和 External Secrets Operator 运行时密钥体系。
8. Crossplane 与 CloudNativePG 提供 PostgreSQL 自助申请。
9. NFSv4 提供 400 GiB 共享文件存储。
10. Development、Staging、Production 三阶段发布流程。
11. 本地敏感信息、操作日志、备份和恢复 Runbook。

## 2. 非目标

第一阶段明确不包含：

1. Proxmox 物理宿主机级高可用。
2. NFS 服务器高可用。
3. 400 GiB 业务数据的异机备份。
4. 公网暴露。
5. 统一 SSO。
6. Harbor Trivy 漏洞扫描。
7. Crossplane 管理承载 K3s 的 Proxmox 虚拟机。
8. 自动升级核心平台版本。
9. 将 Control、Data、Workflow、Observability Plane 拆分到独立集群。

## 3. 物理与虚拟化拓扑

Proxmox VE 地址为 192.168.2.162。宿主机保持现有系统，不由本项目重装或修改底层存储结构。

目标虚拟机：

| VM ID | 主机名 | IP | CPU | 内存 | 系统盘 | 附加盘 | 角色 |
|---|---|---|---:|---:|---:|---:|---|
| 120 | ocp-node-01 | 192.168.2.180 | 4 | 16 GiB | 100 GiB | 无 | K3s Server |
| 121 | ocp-node-02 | 192.168.2.181 | 4 | 16 GiB | 100 GiB | 无 | K3s Server |
| 122 | ocp-node-03 | 192.168.2.182 | 4 | 16 GiB | 100 GiB | 无 | K3s Server |
| 130 | nfs-storage-01 | 192.168.2.183 | 2 | 4 GiB | 32 GiB | 400 GiB | NFSv4 |

VM ID 130、所有 IP 和磁盘目标必须在实施前重新只读核验。发现占用时停止，不自动选择替代值。

四台虚拟机统一使用 Ubuntu 24.04 Cloud Image、Cloud-Init 和 SSH 公钥初始化。三个 K3s 节点资源保持对称，避免调度能力和故障行为不一致。

原三块 200 GiB 空数据盘在最终只读空盘检查后删除。新建一块 400 GiB XJ6T 虚拟磁盘并只挂载给 NFS VM。

## 4. 网络、VIP 与域名

现有网络基线：

| 项目 | 值 |
|---|---|
| 子网 | 192.168.0.0/21 |
| 默认网关 | 192.168.1.1 |
| VM 网桥 | vmbr0 |
| K3s API VIP | 192.168.2.179 |
| 内部域名 | openchoreo.home.arpa |

192.168.2.111 的实际身份未知，不作为平台内部域名的必要依赖。虚拟机外部 DNS 在实施前通过只读检查确定；OpenChoreo 内部域名由专用 CoreDNS 负责。

MetalLB 地址池：

| IP | 用途 |
|---|---|
| 192.168.2.178 | 通用 Ingress NGINX |
| 192.168.2.177 | OpenChoreo Control Plane Gateway |
| 192.168.2.176 | 内部权威 CoreDNS |
| 192.168.2.175 | OpenChoreo Data Plane Gateway |
| 192.168.2.174 | OpenChoreo Observability Gateway |
| 192.168.2.170-173 | 预留 |

所有 VIP 和 MetalLB 地址在实施前执行 ARP、ICMP 和端口占用检查。任何冲突都阻止部署。

域名映射：

| 域名 | 目标 |
|---|---|
| console.openchoreo.home.arpa | 192.168.2.177 |
| api.openchoreo.home.arpa | 192.168.2.177 |
| thunder.openchoreo.home.arpa | 192.168.2.177 |
| argocd.openchoreo.home.arpa | 192.168.2.178 |
| harbor.openchoreo.home.arpa | 192.168.2.178 |
| grafana.openchoreo.home.arpa | 192.168.2.178 |
| observer.openchoreo.home.arpa | 192.168.2.174 |
| *.apps.openchoreo.home.arpa | 192.168.2.175 |

CoreDNS 只对 openchoreo.home.arpa 权威应答，不替代全网 DNS。当前 Mac 通过 /etc/resolver/openchoreo.home.arpa 将该域查询发送给 192.168.2.176。K3s 节点通过 systemd-resolved 的路由域配置解析同一区域。

## 5. TLS

平台仅在内网提供 HTTPS。

1. 在当前 Mac 生成内部根 CA。
2. CA 私钥保存在 openchoreo-infra/.private/pki，权限为 0600。
3. 根证书导入当前 Mac 系统钥匙串。
4. Ansible 将签发材料以 Kubernetes Secret 方式注入。
5. cert-manager 使用 CA ClusterIssuer 签发服务证书。
6. Data Plane 使用 *.apps.openchoreo.home.arpa 通配证书。
7. Git 仓库只保存 Certificate、Issuer 引用和非敏感配置。

CA 私钥、已签发私钥和 Kubeconfig 不进入 Git。

## 6. 两个仓库的责任边界

### 6.1 openchoreo-infra

该仓库负责让 Kubernetes 和 Argo CD 存在，并负责平台从零恢复：

    Proxmox
      -> Terraform
      -> Cloud-Init
      -> Ubuntu
      -> Ansible
      -> K3s
      -> kube-vip
      -> Cilium
      -> Argo CD 核心

职责包括：

- Proxmox VM、磁盘、网络和模板。
- Ubuntu 基线。
- K3s、embedded etcd、kube-vip 和 Cilium。
- Argo CD 核心的首次安装和灾难恢复。
- NFS 服务器。
- 资产、Runbook、操作日志和恢复脚本。
- 本地敏感信息和 Terraform state。

### 6.2 openchoreo-gitops

该仓库负责 Argo CD 运行之后的集群期望状态：

    Argo CD Root Application
      -> 基础平台组件
      -> OpenChoreo
      -> Crossplane
      -> 平台资源
      -> 项目与发布声明

职责包括：

- Root Application、AppProject 和子 Application。
- MetalLB、Ingress NGINX、CoreDNS、cert-manager。
- NFS StorageClass。
- Harbor、OpenBao、ESO。
- OpenChoreo 四个 Plane。
- OpenSearch、Prometheus、Grafana、OpenTelemetry 和 Fluent Bit。
- Crossplane、CloudNativePG、XRD 和 Composition。
- Development、Staging、Production。
- ComponentType、Trait、Workflow、ResourceType、Project 和 ReleaseBinding。

### 6.3 明确禁止双重管理

| 资源 | 唯一管理者 |
|---|---|
| Proxmox VM | Terraform |
| Ubuntu 配置 | Ansible |
| K3s、kube-vip、Cilium | Ansible |
| Argo CD 核心程序 | Ansible |
| Argo Root Application | GitOps |
| K3s 内平台组件 | Argo CD |
| Project、Component、ReleaseBinding 等声明 | GitOps |
| OpenChoreo 渲染出的运行时资源 | OpenChoreo Controller |
| Crossplane XR | GitOps 或 OpenChoreo ResourceType |
| XR 组合出的 PostgreSQL 等资源 | Crossplane |

同一对象不得同时由 Terraform、Ansible、Argo CD 或 Crossplane 持续协调。

## 7. Terraform 与 Cloud-Init

Terraform 使用 Proxmox Provider 管理：

1. Ubuntu Cloud Image 模板。
2. 三台 K3s VM。
3. NFS VM。
4. CPU、内存、系统盘和 NFS 数据盘。
5. 网络接口和 Cloud-Init 参数。

Terraform state 只能写入 .private/terraform-state。仓库提交 provider lock file、变量示例和模块代码，不提交真实 tfvars。

Terraform 不通过 remote-exec 安装 K3s，也不管理 Kubernetes 内资源。

Cloud-Init 仅负责：

- 主机名。
- 静态 IP。
- 默认网关和基础 DNS。
- SSH 公钥。
- cloud-init 用户和最小首次启动配置。

## 8. Ansible 与 K3s

Ansible 负责：

1. Ubuntu 软件源、时区、NTP、内核模块和 sysctl。
2. SSH、安全更新和系统工具。
3. NFSv4 服务、磁盘挂载和导出。
4. 三节点 K3s Server。
5. kube-vip。
6. Cilium。
7. Argo CD 核心。
8. CA、OpenBao 初始化材料和 Harbor 引导密钥的受控注入。

K3s 配置：

- 三节点均为 Server。
- ocp-node-01 执行 cluster-init。
- ocp-node-02、ocp-node-03 顺序加入。
- embedded etcd 三成员。
- tls-san 包含 192.168.2.179。
- 禁用 Flannel。
- 禁用内置 Network Policy Controller。
- 禁用 Traefik。
- 禁用 ServiceLB。
- 保留 kube-proxy，Cilium 第一阶段不启用 kube-proxy replacement。
- 保留 local-path provisioner。

引导顺序：

    第一个 K3s Server
      -> kube-vip
      -> Cilium
      -> 其余两个 K3s Server
      -> 验证 etcd
      -> Argo CD
      -> Root Application

Cilium 必须由 Ansible 管理，因为没有 CNI 时 Argo CD Pod 无法正常运行。

## 9. Argo CD 与同步顺序

Argo CD 核心由 Ansible 以固定版本安装。GitOps 仓库负责 Root Application 和所有子应用。

Root Application 使用 App-of-Apps 模式，并按同步波次部署：

| 波次 | 内容 |
|---:|---|
| 0 | CRD 和 Operator：cert-manager、ESO、Crossplane、CloudNativePG |
| 1 | MetalLB、CoreDNS、Ingress NGINX、NFS StorageClass |
| 2 | OpenBao、ClusterSecretStore、Harbor |
| 3 | OpenChoreo 公共依赖、kgateway |
| 4 | Control Plane |
| 5 | Data Plane、Workflow Plane、Observability Plane |
| 6 | 监控目标、Crossplane Composition、平台公共资源 |
| 7 | Development、Staging、Production、示例项目 |

自动同步和自愈可以启用，但所有 Chart、镜像和配置必须固定版本。Prune 仅对明确由对应 Application 追踪的资源启用，不能清理由 OpenChoreo 或 Argo Workflows 动态生成的运行实例。

WorkflowRun 属于触发型资源，不提交到 GitOps 仓库。

## 10. 存储

### 10.1 NFS VM

- NFSv4。
- 数据目录 /srv/openchoreo。
- 400 GiB 数据盘位于 XJ6T。
- Terraform 管理磁盘。
- Ansible 格式化、挂载、导出和设置权限。
- Argo CD 管理 NFS provisioner 和 StorageClass。

### 10.2 StorageClass

| StorageClass | 默认 | 适用范围 |
|---|---|---|
| nfs-shared | 是 | Harbor 镜像、共享 PVC、构建产物和备份 |
| local-path | 否 | etcd、OpenBao、OpenSearch、Prometheus、数据库 |

OpenSearch 实时索引不得使用 NFS。NFS 可用于 OpenSearch 快照。

### 10.3 数据落点

| 数据 | 存储 |
|---|---|
| Harbor Registry blobs | nfs-shared |
| Workflow 构建产物 | nfs-shared |
| 普通应用共享数据 | nfs-shared |
| 备份导出 | nfs-shared |
| K3s etcd | 节点本地 |
| OpenBao Raft | 三节点 local-path |
| OpenSearch 实时索引 | 三节点 local-path |
| Prometheus TSDB | local-path |
| CloudNativePG 数据 | local-path |
| Harbor PostgreSQL | local-path，逻辑备份到 NFS |

第一阶段本地盘上限：

| 组件 | 容量 |
|---|---:|
| OpenBao | 每节点 5 GiB |
| OpenSearch | 每节点 20 GiB |
| Prometheus | 15 GiB |
| Harbor PostgreSQL | 10 GiB |

每个 100 GiB 系统盘至少保留 20 GiB 安全余量。达到 75% 使用率告警，达到 85% 时停止新增有状态资源并执行容量处理。

## 11. OpenChoreo

四个 Plane 部署在同一个 K3s 集群，通过 Namespace、RBAC、Cilium 和 Gateway 隔离。

### Control Plane

- OpenChoreo API。
- Controller Manager。
- Backstage Console。
- ThunderID。
- Cluster Gateway。

### Data Plane

- 应用 Deployment、Service 和配置。
- kgateway。
- Cilium 网络策略。
- Harbor 拉取凭据。
- OpenBao/ESO Secret 引用。

### Workflow Plane

- Argo Workflows。
- ClusterWorkflowTemplate。
- Git 源代码拉取。
- 构建容器镜像。
- 推送 Harbor。

Argo CD 和 Argo Workflows 分别承担 GitOps 和任务执行，不重复安装 Argo Workflows。

### Observability Plane

- OpenSearch：日志和链路数据。
- Prometheus：指标。
- OpenTelemetry Collector：链路采集。
- Fluent Bit：日志采集。
- Observer API。
- Grafana。

不再安装第二套 kube-prometheus-stack。OpenChoreo 的 Prometheus 额外采集 K3s、etcd、Cilium、Argo CD、Argo Workflows、Harbor、OpenBao、NFS 和 CloudNativePG。

第一阶段默认保留：

- OpenSearch 日志和链路 7 天。
- Prometheus 指标 15 天。
- Argo Workflow 运行记录 7 天。

这些值通过 GitOps 配置，可在容量监控稳定后调整。

## 12. Harbor

Harbor 通过官方 Helm Chart 安装，地址为 harbor.openchoreo.home.arpa。

第一阶段：

- 私有项目 openchoreo。
- 内部 CA HTTPS。
- Registry 数据保存到 NFS。
- PostgreSQL 保存到 local-path。
- 创建 Workflow Plane 推送 Robot Account。
- 创建 Data Plane 只读 Robot Account。
- 管理员、推送和拉取凭据相互分离。
- 每周执行垃圾回收。
- 默认每个仓库保留最近 10 个发布标签。
- 不启用 Trivy。

Harbor Robot Secret 由引导 Playbook 通过 Harbor API 创建后写入 OpenBao，不写入 Git。

## 13. OpenBao 与 ESO

OpenBao 使用生产模式，不使用重启即丢失数据的 dev 模式。

- 三个 Raft 副本。
- 每个 K3s 节点一个。
- 每个副本使用 local-path。
- Pod 反亲和确保分布到三个节点。
- 初始化密钥和恢复密钥保存在 .private/openbao。
- 暂不配置云 KMS 自动解封。
- 全集群重启后由 Ansible 受控执行解封。
- 每日生成 Raft 快照。

External Secrets Operator 创建 ClusterSecretStore/default。OpenChoreo Secret Management 功能显式开启。

秘密边界：

| 类型 | 保存位置 |
|---|---|
| PVE、SSH、Kubeconfig、Terraform state、CA、OpenBao 恢复密钥 | Mac 的 .private |
| Harbor Robot Token、Git 凭据、应用密码 | OpenBao |
| SecretReference、ExternalSecret | GitOps |

## 14. Crossplane 与 CloudNativePG

Crossplane 第一阶段不安装 Proxmox Provider。

首个自助资源 API 为 PostgreSQL：

    OpenChoreo Resource
      -> ClusterResourceType
      -> Crossplane XR
      -> CloudNativePG Cluster
      -> Service 与 Secret
      -> Workload dependency

默认环境规格：

| 环境 | PostgreSQL 副本 | 初始数据盘 |
|---|---:|---:|
| Development | 1 | 2 GiB |
| Staging | 1 | 5 GiB |
| Production | 3 | 每副本 10 GiB |

数据库凭据只在 Data Plane 生成和使用。OpenChoreo Control Plane只保存 Secret 引用。

Crossplane 不管理 Harbor、OpenChoreo、OpenBao、K3s 节点或 NFS VM。

## 15. 环境与发布

创建三个逻辑环境：

    Development
      -> Staging
      -> Production

- 三个环境位于同一个 Data Plane。
- Namespace 和 Cilium 提供逻辑隔离。
- Development 接收新发布。
- Staging 用于预发布验证。
- Production 必须手动批准。
- 同一个不可变 ComponentRelease 逐级提升。
- 各环境使用独立配置和 Secret。

这不是三个物理集群。以后可将 Production 的 Environment 重新绑定到独立 Data Plane。

## 16. 登录

第一阶段不做统一 SSO：

| 服务 | 登录方式 |
|---|---|
| OpenChoreo | ThunderID |
| Argo CD | 本地管理员 |
| Harbor | 本地管理员 |
| Grafana | 本地管理员 |

管理员密码保存在 .private 和受控 Secret 中，不进入 Git。

## 17. 版本和升级

所有核心组件固定具体版本：

- Ubuntu 镜像校验 SHA-256。
- Terraform Provider lock file。
- K3s。
- Cilium。
- kube-vip。
- Argo CD。
- Helm Chart。
- OpenChoreo。
- Harbor。
- Crossplane。
- CloudNativePG。
- OpenBao。

允许 Argo CD 自动同步 Git 中的固定状态，不允许自动选择新版本。

升级流程：

1. 创建分支。
2. 更新一个组件版本。
3. 渲染和静态验证。
4. 阅读发行说明。
5. 创建备份。
6. 合并并由 Argo 同步。
7. 运行组件和端到端验证。
8. 失败时回退 Git 提交或按 Runbook 恢复。

Ubuntu只自动安装安全修复；需要重启或内核变更的升级手动执行。

## 18. 备份与恢复

现阶段没有独立 NAS、外接硬盘或第二台物理服务器，因此无法提供完整异机数据备份。

已确认的有限恢复策略：

| 数据 | 策略 |
|---|---|
| K3s etcd | 每 6 小时快照，保留 14 天 |
| OpenBao | 每日 Raft 快照 |
| Harbor PostgreSQL | 每日逻辑备份到 NFS |
| OpenSearch | 升级前快照到 NFS |
| Terraform state | Mac 本地 .private |
| Kubeconfig、CA、恢复密钥 | Mac 本地 .private |
| 最新关键快照 | Mac 在线时每日拉取 |
| 400 GiB NFS 业务数据 | 无异机备份 |

PVE 快照只用于变更回滚，不视为异机备份。

恢复顺序：

    Terraform 重建 VM
      -> Ansible 恢复 K3s、Cilium、kube-vip
      -> 恢复 etcd 或建立空集群
      -> 安装 Argo CD
      -> GitOps 重建平台
      -> 恢复 OpenBao
      -> 恢复 Harbor 元数据
      -> 恢复应用数据

## 19. 仓库目标结构

### openchoreo-infra

    openchoreo-infra/
    ├── README.md
    ├── AGENTS.md
    ├── SECURITY.md
    ├── inventory/
    ├── terraform/
    │   ├── modules/
    │   └── environments/homelab/
    ├── cloud-init/
    ├── ansible/
    │   ├── inventory/
    │   ├── roles/
    │   └── playbooks/
    ├── runbooks/
    ├── scripts/
    ├── docs/
    ├── logs/
    ├── templates/
    └── .private/

### openchoreo-gitops

    openchoreo-gitops/
    ├── bootstrap/
    │   └── root-application.yaml
    ├── clusters/homelab/
    │   ├── infrastructure/
    │   ├── security/
    │   ├── storage/
    │   ├── registry/
    │   ├── observability/
    │   ├── crossplane/
    │   └── openchoreo/
    ├── platform/
    │   ├── environments/
    │   ├── pipelines/
    │   ├── component-types/
    │   ├── resource-types/
    │   ├── workflows/
    │   └── authorization/
    ├── projects/
    └── legacy-flux/

现有 Flux 示例保留为未启用参考，不向集群安装 Flux。Argo 路径验收后，再通过独立变更决定是否删除旧示例。

## 20. 实施阶段

### 阶段 0：只读预检

- 重新核验 PVE、VM、存储池、磁盘和快照。
- 确认三块 200 GiB 盘为空。
- 确认 VM ID 130 未占用。
- 检测 192.168.2.170-179 和 192.168.2.183。
- 检查 XJ6T 容量。
- 输出 Terraform plan，不修改资源。

### 阶段 1：基础设施代码

- 创建 Terraform、Cloud-Init 和 Ansible 实现。
- 创建私有目录和示例变量。
- 通过静态检查。
- 在任何删除或覆盖前再次请求用户确认。

### 阶段 2：虚拟机重建

- 创建或更新 Ubuntu Cloud Image 模板。
- 删除确认空闲的旧 200 GiB 盘。
- 创建 400 GiB NFS 数据盘。
- 按顺序重建三个 K3s 节点。
- 创建 NFS VM。
- 每台完成 SSH 和磁盘验证后再继续。

### 阶段 3：K3s 基础

- 安装 K3s、kube-vip、Cilium。
- 顺序加入第二和第三节点。
- 验证 etcd、VIP 和 CNI。
- 安装 Argo CD。

### 阶段 4：GitOps 基础平台

- Root Application。
- CRD 和 Operator。
- MetalLB、CoreDNS、Ingress、cert-manager、NFS。
- OpenBao、ESO、Harbor。

### 阶段 5：OpenChoreo 和资源平台

- 四个 Plane。
- Observability。
- Crossplane、CloudNativePG。
- 三阶段环境和公共平台资源。

### 阶段 6：端到端验收

- 构建示例应用。
- 推送 Harbor。
- 部署 Development。
- 提升到 Staging 和 Production。
- 申请 PostgreSQL。
- 验证日志、指标、Secret 和数据库连接。
- 执行单节点故障演练。

## 21. 验证策略

代码阶段：

- terraform fmt -check。
- terraform validate。
- terraform plan。
- ansible-lint。
- Ansible check mode。
- Helm template。
- Kustomize build。
- Kubernetes schema 验证。
- gitleaks 或等价敏感信息扫描。
- git diff --check。

运行阶段：

1. 四台 VM SSH 可达。
2. 三个 K3s Node 为 Ready。
3. Kubernetes API 通过 192.168.2.179 可达。
4. etcd 三成员健康。
5. Cilium 状态健康。
6. MetalLB 地址与设计一致。
7. CoreDNS 正确解析固定和通配域名。
8. Argo Application 全部 Synced 和 Healthy。
9. OpenChoreo 四个 Plane Ready。
10. Harbor push 和 pull 成功。
11. OpenBao、ESO 和 ExternalSecret Ready。
12. 日志、指标和链路可查询。
13. Crossplane XR、Composition 和 CloudNativePG Ready。
14. Development 到 Production 提升成功。
15. 停止任意一个 K3s 节点后 API 保持可用。
16. Git 历史不存在秘密、Kubeconfig 或 Terraform state。

## 22. 成功标准

满足以下条件才算平台建设完成：

- 能从 Git 和本地秘密重建所有虚拟机与 K3s。
- 能由 Argo CD 重建集群内平台组件。
- 能登录并使用 OpenChoreo、Argo CD、Harbor 和 Grafana。
- 能从 Git 源代码构建镜像、推送 Harbor 并部署应用。
- 能执行 Development、Staging、Production 发布。
- 能从 OpenChoreo 申请 PostgreSQL 并注入连接信息。
- 能查看应用日志和指标。
- 能承受单个 K3s VM 故障。
- 已明确证明 PVE、XJ6T 和 NFS VM 仍是单点。

## 23. 风险

1. 所有 VM 位于同一 PVE，物理宿主机故障会导致平台整体停止。
2. NFS VM 和 400 GiB 数据盘是单点。
3. 没有异机业务数据备份。
4. Development、Staging、Production 只是逻辑隔离。
5. 三节点资源足够第一阶段，但 OpenSearch、Harbor 和构建并发必须设置资源限制。
6. OpenBao 没有云 KMS 自动解封，全集群重启后需要受控解封。
7. CoreDNS 运行在同一 K3s 集群；集群完全失效时平台域名不可解析，但基础恢复仍可使用 IP。

## 24. 已确认决策摘要

- 三台 K3s 节点均为 4C/16 GiB/100 GiB。
- 新建 2C/4 GiB NFS VM 和 400 GiB 数据盘。
- 三节点 K3s Server + embedded etcd。
- kube-vip 192.168.2.179。
- Cilium 替换 Flannel，由 Ansible 管理。
- MetalLB 地址池 192.168.2.170-178。
- 内部域名 openchoreo.home.arpa。
- 专用 CoreDNS 192.168.2.176。
- 内部 CA 和 HTTPS。
- 当前仅 Mac 访问。
- Argo CD 管理集群内平台。
- OpenChoreo 四个 Plane 单集群完整安装。
- Harbor，不启用 Trivy。
- OpenBao 三副本 + ESO。
- OpenChoreo Observability 为唯一监控栈。
- 混合使用 NFS 和 local-path。
- Crossplane + CloudNativePG 提供 PostgreSQL。
- Development、Staging、Production 三阶段。
- 各平台暂时分开登录。
- 固定版本、手动批准升级。
- 接受 400 GiB 数据无异机备份。

## 25. 官方参考

- OpenChoreo Deployment Topology：https://openchoreo.dev/docs/platform-engineer-guide/deployment-topology/
- OpenChoreo Runtime Model：https://openchoreo.dev/docs/concepts/runtime-model/
- OpenChoreo Run in Your Environment：https://openchoreo.dev/docs/getting-started/try-it-out/on-your-environment/
- OpenChoreo Secret Management：https://openchoreo.dev/docs/next/platform-engineer-guide/secret-management/
- OpenChoreo ResourceType：https://openchoreo.dev/docs/platform-engineer-guide/resource-types/
- Crossplane Composition：https://docs.crossplane.io/latest/composition/compositions/
- Harbor Helm HA Guide：https://goharbor.io/docs/edge/install-config/harbor-ha-helm/
- OpenSearch Storage Recommendation：https://docs.opensearch.org/latest/install-and-configure/install-opensearch/index/
