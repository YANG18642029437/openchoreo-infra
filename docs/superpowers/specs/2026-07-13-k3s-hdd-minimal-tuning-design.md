# K3s 机械盘最小优化设计

## 背景

三台 K3s 节点是个人实验环境，当前目标是保持 OpenChoreo 可访问和可继续实验，不追求生产级存储隔离。实时观测表明 CPU 和内存充足，但三台节点所在的 `XJ6T` 机械盘存在较高 I/O 等待；节点根文件系统同时启用了持续 `discard` 和每周 `fstrim.timer`。

四块 240 GB SSD 均已有 ext4 分区且处于挂载状态，用途未确认。本次禁止修改、格式化、卸载或重新分配这些 SSD。

## 目标与非目标

### 目标

- 取消三台 K3s 节点根文件系统的持续在线 `discard`。
- 保留 Proxmox 虚拟磁盘的 `discard=on` 能力和 Ubuntu 每周 `fstrim.timer`。
- 逐台滚动执行，并在每台变更后确认根挂载参数、定时器和 Kubernetes Node 状态。
- 将期望状态、验证方式、操作证据和回滚方式保存在 `openchoreo-infra`。

### 非目标

- 不修改 PVE 存储、虚拟磁盘、磁盘控制器或 Terraform state。
- 不使用或审计后重新分配四块 SSD。
- 不迁移 etcd、OpenSearch、Prometheus 或任何 PVC。
- 不修改 OpenChoreo、Argo CD、Harbor、OpenBao 或 Gateway 配置。
- 不通过增加 etcd 超时掩盖磁盘延迟。

## 方案选择

已比较以下方案：

1. 保持现状：没有变更风险，但持续 discard 与每周 fstrim 重复。
2. **最小优化（采用）**：仅取消持续 discard，保留每周 fstrim；改动面最小，适合个人实验环境。
3. SSD 隔离 etcd：稳定性最好，但 SSD 用途未知且改动面明显扩大，本阶段不采用。

## 实现设计

新增一个只作用于 `k3s_servers` 的独立 Ansible playbook，设置 `serial: 1` 和 `any_errors_fatal: true`。它不得复用面向所有主机的 `common` role，以免修改 NFS 和出站代理 VM。

每台节点按以下顺序处理：

1. 断言 `/etc/fstab` 中存在唯一的 `LABEL=cloudimg-rootfs` 根挂载。
2. 备份 `/etc/fstab`，将根挂载选项从 `discard,commit=30,errors=remount-ro` 改为 `defaults,commit=30,errors=remount-ro`。
3. 使用 `mount -o remount,nodiscard /` 使修改即时生效；不停止 K3s、不重启 VM。
4. 确认 `findmnt` 的根挂载选项不包含 `discard`。
5. 确认 `fstrim.timer` 已启用且运行中。
6. 从控制端确认当前 Kubernetes Node 仍为 `Ready`，然后才处理下一台。

Playbook 必须幂等：再次运行时不得重复修改 `/etc/fstab`，但仍执行只读验证。

## 安全边界

- 禁止出现 `mkfs`、`wipefs`、`parted`、`fdisk`、磁盘格式化、卸载根分区或磁盘删除操作。
- 远程写入前创建新的 etcd snapshot，并验证最近一次 PVE VM 全量备份证据。
- 远程写入必须获得执行时确认；本设计审批不能代替执行确认。
- 任何节点验证失败立即停止，不继续下一台。
- 操作日志只记录脱敏状态，不记录密码、私钥、Token 或 kubeconfig 内容。

## 回滚

如果取消持续 discard 后出现异常，在单个节点上：

1. 将根挂载选项恢复为 `discard,commit=30,errors=remount-ro`。
2. 执行 `mount -o remount,discard /`。
3. 验证根挂载包含 `discard`、K3s 服务正常且 Node 为 `Ready`。

其余节点未执行时保持原状。由于不迁移数据、不格式化磁盘，回滚不涉及数据复制。

## 验收标准

- 三台节点 `/etc/fstab` 根挂载均不包含持续 `discard`。
- 三台节点实时根挂载均不包含 `discard`。
- 三台节点 `fstrim.timer` 均为 enabled 和 active。
- 三台 Kubernetes Node 均为 `Ready`。
- Kubernetes API `/readyz` 通过。
- Argo CD、Harbor、OpenBao、OpenChoreo Portal 和 Observer 入口仍可访问。
- 本地验证、Phase 01 门禁和秘密扫描通过。
