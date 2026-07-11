# 内部 DNS 与 PKI Runbook

## 适用范围

本 Runbook 用于当前 Mac 访问 `openchoreo.home.arpa` 内部域名，以及后续导入平台内部根 CA。集群权威 DNS 使用 `192.168.2.157`，通用入口使用 `192.168.2.159`。

原设计地址段 `192.168.2.170-178` 在实施前复核时发现 `.170-.176` 已被多个局域网设备占用，因此实施地址池调整为 `192.168.2.150-159`。不要重新启用冲突地址。

## 配置 Mac split DNS

```bash
./scripts/bootstrap/configure-macos-dns.sh
scutil --dns | grep -A5 openchoreo.home.arpa
dig +short harbor.openchoreo.home.arpa
```

脚本只为 `openchoreo.home.arpa` 创建 `/etc/resolver/openchoreo.home.arpa`，不会替换 Mac 的全局 DNS。

## 验证集群 DNS

```bash
kubectl -n homelab-dns rollout status deployment/homelab-dns
kubectl -n homelab-dns get service homelab-dns
dig @192.168.2.157 harbor.openchoreo.home.arpa
```

期望 DNS Service 的外部地址为 `192.168.2.157`，查询 `harbor.openchoreo.home.arpa` 返回 `192.168.2.159`。

## 敏感信息边界

后续根 CA 私钥只能保存在 `.private/pki/root-ca.key`，权限必须为 `0600`；公开仓库只保存 Certificate、Issuer 等不含密钥值的声明。
