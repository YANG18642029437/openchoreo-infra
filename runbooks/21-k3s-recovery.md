# K3s 恢复 Runbook

## 常规检查

```bash
export KUBECONFIG="$PWD/.private/kubeconfigs/homelab-admin.yaml"
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
kubectl -n argocd get pods -o wide
curl -k -o /dev/null -w '%{http_code}\n' https://192.168.2.179:6443/livez
```

VIP 返回 `200` 或未认证的 `401` 都表示 API 端口可达。一次只恢复一个节点，禁止同时停止两个 etcd 成员。

## 节点重新加入

确认 `.private/tokens/k3s-server-token` 和 SSH 私钥存在，重新执行 `ansible/playbooks/30-k3s.yml`。不得直接删除 `/var/lib/rancher/k3s/server/db/etcd`；成员冲突时先保存 journal、成员列表和快照，再决定是否移除旧成员。

## etcd 快照与恢复

```bash
ssh ubuntu@192.168.2.180 'sudo k3s etcd-snapshot save --name manual-pre-change'
ssh ubuntu@192.168.2.180 'sudo k3s etcd-snapshot ls'
```

恢复快照属于有损操作：先停止全部 K3s 节点、备份现有 datastore，并按 K3s 官方 snapshot restore 流程从一个节点恢复，再逐台加入。不得在普通故障排查中直接执行 `cluster-reset`。

## kube-vip 与 Cilium

```bash
kubectl -n kube-system rollout status daemonset/kube-vip-ds --timeout=10m
kubectl -n kube-system rollout status daemonset/cilium --timeout=10m
kubectl -n kube-system rollout status deployment/cilium-operator --timeout=10m
```

`systemctl stop k3s` 可能保留 containerd shim，因而 kube-vip 容器仍会续租；这不等价于 VM 宕机。完整故障演练应停止 VM，或同时确认故障节点 kube-vip 进程已经退出。恢复后必须检查 lease holder 与 `192.168.2.179/32` 的实际持有节点。

## Argo CD 重新引导

设置本地 chart、image archive 与 kubeconfig 环境变量后重新运行 `ansible/playbooks/40-argocd.yml`。它必须返回幂等结果，并满足：application-controller `1/1`、ApplicationSet `2/2`、repo-server `2/2`、server `2/2`、Redis HA `3/3`、HAProxy `3/3`。

若 Helm 因中断停在 `pending-install`，先确认所有 workload 健康，再用 `helm history argocd -n argocd` 判断是否可回滚到已存在 revision。不要删除 release secret 或命名空间来“重装”。

