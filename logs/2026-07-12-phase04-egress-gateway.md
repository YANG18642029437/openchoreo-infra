# 2026-07-12 Phase 04 出站代理网关操作记录

## 基本信息

- 对象：Proxmox VM131 `egress-gateway-01`
- 地址：`192.168.2.184/21`
- 状态：VM、sing-box、K3s 客户端和 Argo CD 代理配置完成
- 管理方式：Terraform + Ansible

## 原因

三台 K3s 节点和 Argo CD repo-server 均能解析 GitHub 域名，但连接 `github.com:443` 超时。Mac 的 Shadowrocket 代理监听在另一个不可达网段，不能作为服务器长期出口，因此创建独立网关。

## 执行结果

- 迁移 Terraform state、SSH 私钥、kubeconfig 和 known_hosts 到主仓库 `.private/`，后续不再依赖 worktree 路径。
- Terraform 刷新现有 VM 后返回无漂移。
- 实时确认 VM ID 131 与 `192.168.2.184` 空闲。
- Terraform 计划为 1 新增、0 修改、0 删除并执行成功。
- VM 运行 Ubuntu 24.04，SSH 与静态地址正常。
- 从 sing-box 官方 GitHub Release 获取 `1.13.14` linux-amd64 归档，保存在 `.private/artifacts/`。
- Ansible production lint 为 0 错误、0 警告。
- sing-box 二进制、配置目录和 systemd 单元安装成功。
- 用户提供的订阅保存在 `.private/egress/`，选择指定的新加坡节点生成 sing-box 配置；订阅、节点参数和局域网代理凭据均未写入 Git 或日志。
- sing-box 配置检查通过，服务为 `enabled/active`。
- 三台 K3s 节点经代理访问 GitHub 和 MetalLB Chart 均返回 200；Docker Registry 返回未认证时预期的 401。
- K3s systemd 代理环境逐节点安装，每台恢复 `Ready` 后才继续下一台。
- Argo CD repo-server 使用 `egress-proxy` Secret；Root、MetalLB、内部 DNS 和 ingress-nginx Application 均达到 `Synced/Healthy`。
- MetalLB 分配 DNS `192.168.2.157` 与 ingress `192.168.2.159`；权威 DNS 查询和 ingress 404 空路由验证通过。

## 验证摘要

```text
Terraform: 1 added, 0 changed, 0 destroyed
sing-box: 1.13.14 linux/amd64
/usr/local/bin/sing-box: 0755 root:root
/etc/sing-box: 0700 root:root
sing-box.service: enabled, active
GitHub through proxy: HTTP 200
MetalLB chart through proxy: HTTP 200
Docker Registry through proxy: HTTP 401 (expected without authentication)
Argo CD applications: Synced, Healthy
DNS: harbor.openchoreo.home.arpa -> 192.168.2.159
Ingress empty route: HTTP 404
```

## 后续动作

1. 定期检查订阅和指定节点有效性，更新时重新生成受保护配置并由 Ansible部署。
2. 继续 Phase 04 cert-manager、NFS CSI、OpenBao、ESO、Harbor 和 OpenChoreo 部署。
