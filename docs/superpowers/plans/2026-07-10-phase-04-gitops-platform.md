# Phase 04 GitOps Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 在 openchoreo-gitops 中建立 Argo CD App-of-Apps，部署网络入口、内部 DNS/TLS、共享存储、OpenBao/ESO、Harbor 和 OpenChoreo 四个 Plane。

**Architecture:** Argo CD Root Application 只指向 clusters/homelab/applications；每个第三方组件是固定版本的 Helm-source Application，自有配置放在仓库内。密钥值不进入 Git：根 CA、Harbor 初始口令、OpenBao 初始化材料由 openchoreo-infra 的本地引导脚本注入。

**Tech Stack:** Argo CD、Kustomize、Helm、MetalLB 0.16.1、ingress-nginx 4.15.1、CoreDNS、cert-manager 1.19.4、NFS CSI 4.13.4、OpenBao 0.25.6、ESO 2.0.1、Harbor 1.19.1、OpenChoreo 1.1.2。

---

## 目标仓库和文件结构

本阶段修改兄弟仓库 openchoreo-gitops，不在 openchoreo-infra 中混合提交。实施前创建 openchoreo-gitops/.worktrees/codex/openchoreo-platform，并从 origin/main 建分支 codex/openchoreo-platform。

- Create: bootstrap/root-application.yaml
- Create: clusters/homelab/{kustomization.yaml,project.yaml}
- Create: clusters/homelab/applications/*.yaml
- Create: infrastructure/metallb/{kustomization.yaml,ip-address-pool.yaml,l2-advertisement.yaml}
- Create: infrastructure/dns/{kustomization.yaml,configmap.yaml,service.yaml,deployment.yaml}
- Create: infrastructure/ingress/{kustomization.yaml,values.yaml}
- Create: infrastructure/cert-manager/{kustomization.yaml,cluster-issuer.yaml,certificates.yaml}
- Create: infrastructure/storage/{kustomization.yaml,nfs-storage-class.yaml}
- Create: infrastructure/openbao/{kustomization.yaml,values.yaml}
- Create: infrastructure/external-secrets/{kustomization.yaml,cluster-secret-store.yaml}
- Create: platform/harbor/{kustomization.yaml,values.yaml,external-secrets.yaml}
- Create: platform/openchoreo/{kustomization.yaml,values-common.yaml,control-plane.yaml,data-plane.yaml,workflow-plane.yaml,observability-plane.yaml}
- Create: platform/observability/{kustomization.yaml,values-logs.yaml,values-traces.yaml,values-metrics.yaml}
- Create: scripts/verify/{render.sh,policies.sh,secrets.sh,applications.sh}
- Create in infra: scripts/bootstrap/{inject-root-ca.sh,initialize-openbao.sh,configure-macos-dns.sh}
- Create in infra: runbooks/{30-gitops-bootstrap.md,31-pki-and-dns.md,32-openbao-recovery.md}

## Task 1: 建立 GitOps 仓库契约和 Root Application

**Files:**

- Create: scripts/verify/render.sh
- Create: scripts/verify/policies.sh
- Create: scripts/verify/secrets.sh
- Create: bootstrap/root-application.yaml
- Create: clusters/homelab/kustomization.yaml
- Create: clusters/homelab/project.yaml

- [ ] **Step 1: 写会失败的渲染脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
required=(bootstrap/root-application.yaml clusters/homelab/kustomization.yaml clusters/homelab/project.yaml)
for path in "${required[@]}"; do
  test -f "$path" || { printf 'missing GitOps file: %s\n' "$path" >&2; exit 1; }
done
kustomize build clusters/homelab >/tmp/openchoreo-homelab.yaml
kubectl apply --dry-run=client -f /tmp/openchoreo-homelab.yaml >/dev/null
printf 'gitops render: PASS\n'
~~~

- [ ] **Step 2: 运行并确认失败**

~~~bash
chmod +x scripts/verify/render.sh
./scripts/verify/render.sh
~~~

Expected: missing GitOps file: bootstrap/root-application.yaml。

- [ ] **Step 3: 写 AppProject**

AppProject 只允许源仓库当前 GitHub URL和明确列出的官方 Helm 仓库；destination 只允许当前集群。namespaceResourceWhitelist 包括 Namespace，clusterResourceWhitelist 只包含各组件确实需要的 CRD、ClusterRole、ClusterRoleBinding、StorageClass、GatewayClass、ClusterIssuer。

- [ ] **Step 4: 写 Root Application**

~~~yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: homelab-root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/YANG18642029437/openchoreo-gitops.git
    targetRevision: codex/openchoreo-platform
    path: clusters/homelab
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
~~~

实施前用 git remote get-url origin 再核对 URL；合并到 main 后将 targetRevision 改为固定提交 SHA 或 main 的受保护发布提交，不使用 HEAD。

- [ ] **Step 5: 写策略与秘密扫描**

policies.sh 必须拒绝 targetRevision 为空、latest 镜像、未固定 Helm chart、active Flux Kustomization/HelmRelease。secrets.sh 必须拒绝 Secret.data、Secret.stringData、私钥、Token 和口令值，但允许 ExternalSecret、ClusterSecretStore 与空的 Secret 元数据模板。

~~~bash
./scripts/verify/render.sh
./scripts/verify/policies.sh
./scripts/verify/secrets.sh
git add bootstrap clusters scripts/verify
git commit -m "feat: add Argo CD root application"
~~~

Expected: 三个脚本均输出 PASS。

## Task 2: 部署 LoadBalancer、入口、权威 DNS 和 macOS split DNS

**Files:**

- Create: clusters/homelab/applications/{00-metallb.yaml,01-dns.yaml,02-ingress-nginx.yaml}
- Create: infrastructure/metallb/{kustomization.yaml,ip-address-pool.yaml,l2-advertisement.yaml}
- Create: infrastructure/dns/{kustomization.yaml,configmap.yaml,service.yaml,deployment.yaml}
- Create: infrastructure/ingress/{kustomization.yaml,values.yaml}
- Create in infra: scripts/bootstrap/configure-macos-dns.sh
- Create in infra: runbooks/31-pki-and-dns.md

- [ ] **Step 1: 创建固定版本 Applications**

MetalLB Application 使用 chart 0.16.1；ingress-nginx 使用 chart 4.15.1；自有 DNS 清单使用仓库 Kustomize source。同步顺序为 MetalLB -30、DNS -20、ingress -20。

- [ ] **Step 2: 写地址池和入口地址**

~~~yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab
  namespace: metallb-system
spec:
  addresses:
    - 192.168.2.170-192.168.2.178
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab
  namespace: metallb-system
spec:
  ipAddressPools: [homelab]
~~~

ingress-nginx Service 通过 annotation/负载均衡 IP 固定为 192.168.2.178；OpenChoreo 其余网关在对应 Plane values 中固定为 .177、.175、.174。

- [ ] **Step 3: 写权威 CoreDNS**

CoreDNS Deployment 两副本，Service type LoadBalancer、loadBalancerIP 192.168.2.176。zone openchoreo.home.arpa 的 A 记录至少包含 argocd、harbor、openbao、grafana、openchoreo、api、data、workflow、observability，Web UI 指向 .178，Plane Gateway 指向各自固定 IP。

- [ ] **Step 4: 写 Mac split DNS 脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail
resolver=/etc/resolver/openchoreo.home.arpa
sudo install -d -m 0755 /etc/resolver
tmp="$(mktemp)"
printf 'nameserver 192.168.2.176\nport 53\ntimeout 5\n' > "$tmp"
sudo install -m 0644 "$tmp" "$resolver"
rm -f "$tmp"
dscacheutil -flushcache
sudo killall -HUP mDNSResponder
dig +short harbor.openchoreo.home.arpa
~~~

- [ ] **Step 5: 渲染、提交和同步**

~~~bash
./scripts/verify/render.sh
git add clusters/homelab/applications infrastructure/{metallb,dns,ingress}
git commit -m "feat: add platform network foundation"
kubectl -n argocd apply -f bootstrap/root-application.yaml
argocd app wait homelab-root --health --sync --timeout 900
~~~

Expected: .176 DNS、.178 ingress 均由 MetalLB 宣告；Mac 能解析内部域名。

## Task 3: 部署 cert-manager、内部 CA 和 NFS CSI

**Files:**

- Create: clusters/homelab/applications/{03-cert-manager.yaml,04-nfs-csi.yaml,05-platform-certificates.yaml}
- Create: infrastructure/cert-manager/{kustomization.yaml,cluster-issuer.yaml,certificates.yaml}
- Create: infrastructure/storage/{kustomization.yaml,nfs-storage-class.yaml}
- Create in infra: scripts/bootstrap/inject-root-ca.sh

- [ ] **Step 1: 创建根 CA 和集群签发材料**

根 CA 私钥只创建在 openchoreo-infra/.private/pki/root-ca.key，权限 0600；证书在 .private/pki/root-ca.crt。脚本用 kubectl create secret tls homelab-root-ca --dry-run=client -o yaml | kubectl apply -f - 注入 cert-manager 命名空间，不输出私钥内容。

- [ ] **Step 2: 写 ClusterIssuer 与证书**

ClusterIssuer 引用 homelab-root-ca。Certificate 必须覆盖 argocd、harbor、openbao、grafana、openchoreo 和 OpenChoreo API/Plane 域名；Secret 只由 cert-manager 生成。

- [ ] **Step 3: 安装 NFS CSI 和 StorageClass**

NFS CSI Application 固定 chart 4.13.4。nfs-shared StorageClass 使用 server=192.168.2.183、share=/，mountOptions 包含 nfsvers=4.1、hard、timeo=600、retrans=2，reclaimPolicy=Retain，volumeBindingMode=Immediate。local-path 保持存在但不标记 default；nfs-shared 标记默认。

- [ ] **Step 4: 信任 CA 并验证**

~~~bash
security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db \
  openchoreo-infra/.private/pki/root-ca.crt
curl --cacert openchoreo-infra/.private/pki/root-ca.crt \
  https://harbor.openchoreo.home.arpa/v2/
~~~

Expected: TLS 校验通过；Harbor 未就绪时可为 404/401，但不得是证书错误。

- [ ] **Step 5: 提交**

~~~bash
git add clusters/homelab/applications infrastructure/{cert-manager,storage}
git commit -m "feat: add internal PKI and shared storage"
~~~

## Task 4: 部署 OpenBao、ESO 和 Harbor

**Files:**

- Create: clusters/homelab/applications/{06-openbao.yaml,07-external-secrets.yaml,08-harbor.yaml}
- Create: infrastructure/openbao/{kustomization.yaml,values.yaml}
- Create: infrastructure/external-secrets/{kustomization.yaml,cluster-secret-store.yaml}
- Create: platform/harbor/{kustomization.yaml,values.yaml,external-secrets.yaml}
- Create in infra: scripts/bootstrap/initialize-openbao.sh
- Create in infra: runbooks/32-openbao-recovery.md

- [ ] **Step 1: 写 OpenBao 生产 values**

使用 chart 0.25.6/app 2.4.4，server.ha.enabled=true、replicas=3、raft.enabled=true、dataStorage.storageClass=local-path、10Gi，不启用 dev 模式。UI 通过 ingress-nginx 和内部 TLS 暴露；Pod 使用 anti-affinity 分散到三节点。

- [ ] **Step 2: 初始化并解封 OpenBao**

initialize-openbao.sh 先检查未初始化状态，只执行一次 operator init；恢复密钥与初始 root token 直接保存到 .private/openbao，0600，不写 stdout。脚本逐个 Pod 执行 unseal，创建 ESO Kubernetes auth、最小读取策略和 openchoreo KV v2 mount。

- [ ] **Step 3: 安装 ESO 和 ClusterSecretStore**

ESO Application 固定 2.0.1。ClusterSecretStore 指向 https://openbao.openbao.svc:8200、path openchoreo、version v2，以 Kubernetes auth ServiceAccount 登录。先创建一个 canary ExternalSecret 验证同步，再部署 Harbor。

- [ ] **Step 4: 写 Harbor values**

使用 chart 1.19.1/app 2.15.2；禁用 Trivy；registry 持久卷使用 nfs-shared，database/redis/jobservice 使用 local-path；externalURL 为 https://harbor.openchoreo.home.arpa；admin 初始口令和数据库密码来自 ExternalSecret。创建 private 项目 openchoreo，以及 push/pull 分离的 robot account，凭据写回 OpenBao。

- [ ] **Step 5: 验证 push/pull 并提交**

~~~bash
docker login harbor.openchoreo.home.arpa
docker pull registry.k8s.io/pause:3.10
docker tag registry.k8s.io/pause:3.10 harbor.openchoreo.home.arpa/openchoreo/smoke:3.10
docker push harbor.openchoreo.home.arpa/openchoreo/smoke:3.10
docker pull harbor.openchoreo.home.arpa/openchoreo/smoke:3.10
~~~

Expected: push robot 可 push，pull robot 只能 pull；Trivy Pod 不存在。

~~~bash
git add clusters/homelab/applications infrastructure/{openbao,external-secrets} platform/harbor
git commit -m "feat: deploy Harbor and secret management"
~~~

## Task 5: 部署 OpenChoreo 四个 Plane 和唯一 Observability 栈

**Files:**

- Create: clusters/homelab/applications/{09-openchoreo-dependencies.yaml,10-openchoreo-control-plane.yaml,11-openchoreo-data-plane.yaml,12-openchoreo-workflow-plane.yaml,13-openchoreo-observability-plane.yaml}
- Create: platform/openchoreo/{kustomization.yaml,values-common.yaml,control-plane.yaml,data-plane.yaml,workflow-plane.yaml,observability-plane.yaml}
- Create: platform/observability/{kustomization.yaml,values-logs.yaml,values-traces.yaml,values-metrics.yaml}
- Create: scripts/verify/applications.sh

- [ ] **Step 1: 固定兼容依赖和同步波次**

Gateway API v1.4.1、kgateway v2.2.1、cert-manager v1.19.4、ESO 2.0.1 必须在 OpenChoreo 前健康。Control Plane wave 10，Data Plane wave 20，Workflow Plane wave 30，Observability Plane wave 40。不要安装 Flux、第二套 Argo CD 或 kube-prometheus-stack。

- [ ] **Step 2: 写公共 values**

统一 registry 为 harbor.openchoreo.home.arpa/openchoreo；域名后缀 openchoreo.home.arpa；control/data/observability gateway IP 分别为 192.168.2.177、.175、.174；Workflow Plane 安装 Argo Workflows 到独立命名空间，不复用 argocd 命名空间。

- [ ] **Step 3: 部署四个 Plane**

使用 OpenChoreo release v1.1.2 的官方 Helm chart/manifest 路径和对应 CRD。所有镜像 tag 固定；所有 Secret 通过 ExternalSecret 引用；组件级 PVC 按设计选择 nfs-shared 或 local-path。

- [ ] **Step 4: 部署唯一 Observability 栈**

OpenChoreo logs 0.4.1、traces 0.4.1、metrics 0.6.1；OpenSearch、Prometheus 本地盘，Fluent Bit 节点采集，OTEL 接收 traces，Grafana 通过内部 ingress。禁止再安装另一套日志、指标或 tracing 栈。

- [ ] **Step 5: 写 Application 健康验证**

applications.sh 必须列出所有 Argo Application，要求 Sync=Synced、Health=Healthy；检查四个 Plane deployment/statefulset rollout；检查 .177/.175/.174 Service external IP；检查没有 Flux controller 或重复 Prometheus operator。

~~~bash
./scripts/verify/render.sh
./scripts/verify/policies.sh
./scripts/verify/secrets.sh
./scripts/verify/applications.sh
git add clusters/homelab/applications platform/{openchoreo,observability} scripts/verify/applications.sh
git commit -m "feat: deploy OpenChoreo planes"
~~~

Expected: 所有 Application Synced/Healthy，四个 Plane Ready。

## 阶段完成条件

- Root Application 与所有子 Application 都使用固定版本并健康。
- .176 DNS、.178 ingress、.177 control、.175 data、.174 observability 均可达。
- Mac 仅通过 split DNS 访问 openchoreo.home.arpa，HTTPS 证书受信任。
- NFS CSI、OpenBao Raft、ESO canary、Harbor push/pull 通过。
- OpenChoreo 四 Plane Ready；Argo Workflows 与 Argo CD 命名空间和职责分离。
- Git 历史不存在明文 Secret、私钥、Token 或 kubeconfig。
