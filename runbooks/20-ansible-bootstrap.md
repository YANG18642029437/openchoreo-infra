# Ansible 引导 Runbook

## 边界

本 Runbook 只引导 Ubuntu 基线、NFS、K3s、kube-vip、Cilium 和 Argo CD 核心。OpenChoreo 平台 Root Application 属于 Phase 04，不在本阶段创建。

敏感数据仅保存在 `.private/`：SSH 私钥、K3s token、kubeconfig、镜像与 chart 缓存均不得提交。K3s token 的路径为 `.private/tokens/k3s-server-token`，Mac kubeconfig 的路径为 `.private/kubeconfigs/homelab-admin.yaml`。

## 执行顺序

```bash
export PATH="$PWD/.private/ansible-venv/bin:$PATH"
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
export OPENCHOREO_SSH_KEY="<受保护的 SSH 私钥绝对路径>"
export OPENCHOREO_KNOWN_HOSTS="$PWD/.private/known_hosts"

./scripts/verify/ansible.sh
ansible-playbook ansible/playbooks/00-preflight.yml
ansible-playbook ansible/playbooks/10-common.yml
ansible-playbook ansible/playbooks/20-nfs.yml
ansible-playbook ansible/playbooks/30-k3s.yml
./scripts/bootstrap/export-kubeconfig.sh
ansible-playbook ansible/playbooks/40-argocd.yml
```

执行 K3s 和 Argo CD playbook 前还必须设置对应的本地 token、binary、air-gap archive、chart 和 image archive 环境变量；变量名以各 role defaults 中的 `lookup('env', ...)` 为准。不要把变量值写入可提交文档或 shell history。

## 验证

```bash
export KUBECONFIG="$PWD/.private/kubeconfigs/homelab-admin.yaml"
./scripts/verify/nfs.sh
./scripts/verify/cluster-foundation.sh
kubectl get nodes
kubectl -n argocd get deploy,statefulset
helm status argocd -n argocd
```

期望三节点为 `Ready`，Cilium 与 kube-vip DaemonSet 完整 rollout，Argo CD release 为 `deployed`。Argo CD 核心不应包含 Phase 04 Root Application。

## 慢盘保护

现场 embedded etcd 曾观测到 1–10 秒写入或线性读延迟。K3s role 因此固定了较宽的 etcd 和控制组件选举窗口，并启用 `.cache.json` 条件镜像导入。不要删除缓存文件或擅自缩短租约；修改前先完成磁盘延迟基准和 etcd 快照。

