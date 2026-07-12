# 2026-07-12 Phase 04 出站代理网关操作记录

## 基本信息

- 对象：Proxmox VM131 `egress-gateway-01`
- 地址：`192.168.2.184/21`
- 状态：VM 与 sing-box 安装完成，等待上游配置
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
- 未提供上游节点配置，因此服务按安全设计保持 `disabled/inactive`。

## 验证摘要

```text
Terraform: 1 added, 0 changed, 0 destroyed
sing-box: 1.13.14 linux/amd64
/usr/local/bin/sing-box: 0755 root:root
/etc/sing-box: 0700 root:root
sing-box.service: disabled, inactive
```

## 后续动作

1. 将用户提供的上游订阅或节点配置转换为 `.private/egress/config.json`。
2. 通过 Ansible 校验并启用 sing-box。
3. 验证 GitHub、Helm 和镜像仓库出口。
4. 为 Argo CD repo-server 与 K3s/containerd 配置代理并恢复 Phase 04 同步。
