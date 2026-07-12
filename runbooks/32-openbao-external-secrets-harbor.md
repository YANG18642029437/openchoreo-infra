# OpenBao、External Secrets 与 Harbor Runbook

## 目标状态

- OpenBao 使用 3 副本 Raft HA，数据位于各节点的 `local-path` PVC。
- External Secrets Operator 使用 Kubernetes Auth 读取 OpenBao 的 `openchoreo/` KV v2。
- Harbor 通过 Argo CD 管理，Trivy 关闭；Registry 使用 100Gi `nfs-shared`，数据库与 Redis 使用 `local-path`。
- Harbor 管理员密码、内部共享密钥和 robot 凭据不进入 Git。

## 初始化 OpenBao

确认 `openbao-0` 已运行后执行：

```bash
export KUBECONFIG="$PWD/.private/kubeconfigs/homelab-admin-direct.yaml"
./scripts/bootstrap/initialize-openbao.sh
```

脚本可重复执行，负责初始化和解封 3 个实例、建立 Raft 集群、启用 KV v2 与 Kubernetes Auth，并创建 ESO 读取策略。初始化材料写入 `.private/openbao/init.json`，Harbor 引导变量写入 `.private/openbao/harbor.env`；两者必须保持 `0600` 且不得提交 Git。

## 验证 ESO 链路

```bash
kubectl get clustersecretstore openbao
kubectl -n external-secrets get externalsecret openbao-canary harbor-secrets
kubectl -n external-secrets get pods
```

两个 ExternalSecret 和 ClusterSecretStore 都应为 `Ready=True`。验证 Secret 时只列键名，不读取 `.data` 的值。

## Harbor NFS 权限

NFSv4 使用 `root_squash`；动态 PVC 目录的属主会显示为 `65534:65534`。Harbor Registry 以 `10000:10000` 运行，因此 GitOps values 包含一个 init container，在每次 Pod 启动时执行 `chmod 2777 /storage`。不要将 NFS 全局导出改为 `no_root_squash`。

验证：

```bash
kubectl -n harbor exec deployment/harbor-registry -c registry -- \
  stat -c '%a %u:%g' /storage
```

期望权限为 `2777`。如果旧 PVC 在 init container 上线前创建，可在 NFS VM 上仅修复对应 PVC 目录，禁止递归修改整个 `/srv/openchoreo/shared`。

## Harbor 与 Argo CD

Harbor Chart 会随机渲染内部 Secret。Application 对 Harbor Secret 的 `/data` 和 Deployment Pod 模板 checksum 注解设置了 `ignoreDifferences`，并启用 `RespectIgnoreDifferences`，从而保留安全引导时写入的值并阻止无意义滚动重启。

```bash
kubectl -n argocd get application harbor
kubectl -n harbor get pods,pvc,ingress
```

期望 Argo 为 `Synced/Healthy`，所有 Harbor Pod Ready，Registry PVC 为 100Gi RWX。

## Mac 访问限制

Mac 上的透明代理会把内部域名解析为 `198.18.0.0/15` Fake-IP。在完成 split DNS 前，用 `curl --resolve` 做管理验证：

```bash
curl --resolve harbor.openchoreo.home.arpa:443:192.168.2.159 \
  --cacert .private/pki/root-ca.crt \
  https://harbor.openchoreo.home.arpa/v2/
```

未认证返回 `401` 即代表 TLS、Ingress 和 Registry API 正常。要让 Docker/Skopeo 直接使用域名，仍需执行 `./scripts/bootstrap/configure-macos-dns.sh` 并信任 `.private/pki/root-ca.crt`。
