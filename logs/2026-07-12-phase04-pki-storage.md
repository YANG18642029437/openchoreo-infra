# 2026-07-12 Phase 04 PKI 与共享存储操作记录

## 基本信息

- 集群：`openchoreo-homelab`
- 状态：集群侧完成，Mac sudo 步骤待用户执行
- 管理方式：Argo CD + 本地受保护 CA 注入脚本

## PKI 结果

- cert-manager Chart `v1.19.4` 已部署。
- controller、webhook、cainjector 均为双副本并完成 rollout。
- 根 CA 私钥和证书保存在 `.private/pki/`，权限 `0600`，未提交 Git。
- `homelab-root-ca` ClusterIssuer 为 Ready。
- `platform-ingress-tls` Certificate 为 Ready。
- Mac split DNS 和根 CA 信任需要本机 sudo，当前未执行。

## NFS CSI 结果

- NFS CSI Chart `4.13.4` 已部署。
- controller 为 2 副本，node DaemonSet 为 3/3。
- `nfs-shared` 是唯一默认 StorageClass；`local-path` 保留但不再默认。
- 动态卷路径使用 NFSv4 `/shared`，避免给 `/srv/openchoreo` 导出根目录写权限。
- StorageClass 使用 `Retain` 回收策略。

## 真实验证

首次 PVC 测试使用 share `/`，因 root-squash 无权在导出根创建目录而失败。修正为 `/shared` 后：

```text
PVC phase: Bound
Pod phase: Succeeded
Read/write result: phase04-nfs-ok
NFS CSI smoke: PASS
```

测试 Pod、PVC 和 PV 已清理；`Retain` 策略在 NFS 上保留测试目录，符合回收策略语义。

## 后续动作

1. 在 Mac 终端执行 `./scripts/bootstrap/configure-macos-dns.sh` 并输入 sudo 密码。
2. 将 `.private/pki/root-ca.crt` 导入 Mac 登录钥匙串并设为受信任根。
3. 继续部署 OpenBao、External Secrets Operator 和 Harbor。
