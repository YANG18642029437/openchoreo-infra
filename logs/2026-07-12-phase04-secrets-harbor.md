# 2026-07-12 Phase 04 OpenBao、ESO 与 Harbor 操作记录

## 结果

- OpenBao Chart `0.25.6`，应用 `2.5.1`；3 个 Raft 副本全部 Ready。
- External Secrets Operator Chart `2.0.1`；controller、webhook、cert-controller 各 2 副本全部 Ready。
- `ClusterSecretStore/openbao` 和 canary ExternalSecret 均为 Ready。
- Harbor Chart `1.19.1`，应用 `2.15.1`；Trivy 已关闭。
- Harbor Argo Application 最终为 `Synced / Healthy / Succeeded`。
- `openchoreo` private project 已创建；push 与 pull-only robot 凭据已写入 OpenBao。

## 存储

- Registry：100Gi、RWX、`nfs-shared`。
- PostgreSQL：10Gi、RWO、`local-path`。
- Redis：5Gi、RWO、`local-path`。
- Jobservice 使用 stdout 日志，不再申请独立日志 PVC。

首次 Registry 写入失败，服务端错误为 NFS `/storage/docker` permission denied。根因是 `root_squash` 下动态目录为 `65534:65534` 且权限 `2775`，Registry UID 10000 无写权限。仅修复 Harbor PVC 目录为 `2777`，并将权限 init container 纳入 GitOps；没有修改 NFS 导出的 `root_squash` 安全策略。

## 验证证据

```text
Harbor authenticated API status: 200
Harbor OCI manifest push: PASS
Harbor pull-only manifest pull: PASS
Harbor pull-only upload denial: PASS (401)
Harbor hard-refresh pod stability: PASS
```

OCI 验证通过 `curl --resolve` 直接访问 `192.168.2.159`，绕开 Mac 透明代理的 Fake-IP DNS。验证过程中没有输出管理员、robot、OpenBao Token 或 Secret 数据。

## 已知待办

- Mac split DNS 和根 CA 信任仍需要用户在本机 sudo/钥匙串界面完成。
- Kubernetes API VIP `192.168.2.179:6443` 曾出现一次短暂超时；3 个控制节点直连 `:6443` 均可用，本次后续操作使用受保护的 direct kubeconfig。
