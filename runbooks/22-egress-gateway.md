# 出站代理网关 Runbook

## 适用范围

VM131 `egress-gateway-01`（`192.168.2.184`）为三台 K3s 节点、Argo CD repo-server 和 containerd 提供受控的 HTTP/HTTPS 出口。该 VM 由 Terraform 管理，sing-box 由 Ansible 管理。

## 当前状态

- VM：已创建并运行，2 CPU、2 GiB 内存、32 GiB 系统盘。
- 操作系统：Ubuntu 24.04 LTS。
- sing-box：`1.13.14`，安装在 `/usr/local/bin/sing-box`。
- systemd 单元：`/etc/systemd/system/sing-box.service`。
- 服务：已配置并保持 `enabled/active`。

不要用直连出站伪造 GitHub 可用性。订阅更新后必须重新执行配置检查和三类真实出口验证。

## 敏感信息边界

上游订阅、节点凭据和最终 `config.json` 只允许保存在：

```text
.private/egress/
```

目录权限为 `0700`，文件权限为 `0600`。配置通过 `SING_BOX_CONFIG_PATH` 注入，Ansible 任务使用 `no_log`，不得把内容写入 Git、操作日志或终端输出。

## 安装或更新 sing-box

```bash
export PATH="$PWD/.private/ansible-venv/bin:$PATH"
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
export ANSIBLE_SSH_ARGS="-o UserKnownHostsFile=$PWD/.private/known_hosts -o StrictHostKeyChecking=yes"
export OPENCHOREO_SSH_KEY="$PWD/.private/ssh/openchoreo_ed25519"
export SING_BOX_ARCHIVE="$PWD/.private/artifacts/sing-box/sing-box-1.13.14-linux-amd64.tar.gz"

ansible-playbook -i inventory/hosts.yaml ansible/playbooks/15-egress-gateway.yml
```

默认只安装，不启用服务。

## 注入配置并启用

```bash
export SING_BOX_CONFIG_PATH="$PWD/.private/egress/config.json"
ansible-playbook -i inventory/hosts.yaml ansible/playbooks/15-egress-gateway.yml \
  -e egress_gateway_sing_box_enable=true
```

Role 会先运行 `sing-box check`；配置失败时不得继续为 K3s 或 Argo CD设置代理。

## 验证

```bash
ssh ubuntu@192.168.2.184 'systemctl is-active sing-box && sing-box version'
curl --proxy http://192.168.2.184:3128 https://github.com/
```

功能验证必须覆盖 GitHub、Helm Chart 仓库和至少一个容器镜像仓库。随后再配置节点 containerd 与 Argo CD 的 `HTTP_PROXY`、`HTTPS_PROXY` 和 `NO_PROXY`。

## 回滚

```bash
ssh ubuntu@192.168.2.184 'sudo systemctl disable --now sing-box'
```

停止代理后同步撤销 Argo CD 和 containerd 的代理环境变量，避免请求持续指向不可用网关。VM 删除属于 Terraform 破坏性操作，必须单独查看计划并再次确认。
