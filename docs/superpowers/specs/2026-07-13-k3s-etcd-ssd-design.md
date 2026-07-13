# K3s etcd SSD 迁移设计

## 背景

三台 K3s server VM 120、121、122 当前运行 embedded etcd，系统盘均为 `XJ6T` 上的 100 GiB `scsi0`。机械盘 I/O 延迟会直接影响 etcd WAL、快照和 Kubernetes 控制器。本环境是个人实验项目，接受一块物理 SSD 同时承载三个节点的数据盘，但不允许三台 VM 共同挂载同一个块设备或 etcd 数据目录。

PVE 只读核对确认 `SSD1` 是目录存储，路径为 `/mnt/SSD1`，底层为 `/dev/sdg1`：Crucial `CT240BX500SSD1`，序列号 `2047E4CBA2D4`，ext4，容量约 235 GiB，S.M.A.R.T. 状态为 `PASSED`。`terraform@pve` 已在 `/storage/SSD1` 获得现有 `OpenChoreoTerraform` 角色，`Datastore.Allocate` 和 `Datastore.AllocateSpace` 权限有效。

## 目标与非目标

### 目标

- 在同一块物理 `SSD1` 上为 VM 120、121、122 分别创建一块独立的 20 GiB `scsi1` 虚拟磁盘。
- 逐台将 `/var/lib/rancher/k3s/server/db` 迁移到对应节点的 SSD 数据盘。
- 保持 K3s 数据目录路径不变，使用永久挂载和 bind mount 表达期望状态。
- 在每个节点迁移后验证文件系统、K3s、Kubernetes Node 和 embedded etcd 健康，再处理下一台。
- 保留原机械盘数据和迁移前 etcd snapshot，提供明确回滚路径。

### 非目标

- 不迁移 `/var/lib/rancher/k3s` 的 containerd、镜像、agent 或其他运行数据。
- 不迁移 VM 系统盘，不删除或缩小现有 `scsi0`。
- 不让三台 VM 共享同一个虚拟块设备、ext4 文件系统或 etcd 数据目录。
- 不修改 OpenChoreo、Argo CD、Harbor、OpenBao、Gateway、NFS 或出站代理配置。
- 不把一次性磁盘迁移自动加入日常 `site.yml`。
- 不在设计审批或 Terraform plan 阶段执行 `terraform apply`、格式化来宾磁盘或停止 K3s。

## 方案比较与选择

已比较以下 etcd 路径接入方式：

1. **SSD 文件系统加 bind mount（采用）**：数据盘挂载到 `/var/lib/rancher/k3s-ssd`，其中的 `db` bind mount 到 `/var/lib/rancher/k3s/server/db`。原路径保持不变，机械盘原数据在 bind mount 下方保留，回滚边界清晰。
2. 直接挂载到 `server/db`：配置项较少，但 ext4 的 `lost+found` 会进入 etcd 目录，文件系统与应用目录边界不清晰。
3. 符号链接：实现简单，但依赖挂载和服务启动顺序，挂载失败时行为不如 bind mount 明确。

## Terraform 设计

扩展 `proxmox-cloud-vm` 模块，使可选数据盘拥有独立的 datastore 参数。未指定时仍回退到系统盘的 `datastore_id`，因此 VM130 的既有 400 GiB 数据盘行为保持不变。

K3s 节点模块调用统一声明：

- `data_disk_gib = 20`
- `data_disk_datastore_id = "SSD1"`
- 接口保持 `scsi1`
- `iothread = true`
- `discard = "on"`
- `ssd = true`

Terraform plan 必须只包含 VM 120、121、122 各新增一块磁盘。出现 VM replacement、删除、系统盘修改、网络修改或其他资源变更时停止，不得 apply。

## Ansible 迁移设计

新增独立的 `k3s_etcd_ssd` role 和专用 playbook。Playbook 只作用于 `k3s_servers`，设置 `serial: 1` 和 `any_errors_fatal: true`，不导入 `site.yml`。

每台节点按以下顺序处理：

1. 收集块设备、文件系统、挂载点和 K3s 状态。
2. 要求恰好存在一块容量在 19–21 GiB、无文件系统、无挂载点且不是根设备的新磁盘；否则失败。
3. 从控制节点确认 Kubernetes Node 当前为 `Ready`。
4. 创建命名的 etcd snapshot，并确认快照出现在列表中。
5. 停止当前节点的 `k3s` 服务。
6. 再次核对目标设备路径、容量、无文件系统、无挂载点和非系统盘条件。
7. 将目标磁盘格式化为 ext4，并使用 UUID 写入 `/etc/fstab`，挂载到 `/var/lib/rancher/k3s-ssd`，选项为 `defaults,noatime,errors=remount-ro`。
8. 创建 SSD 上的 `db` 目录，通过 `rsync -aHAX --numeric-ids` 复制原 `server/db`，并执行源目标文件数量和总字节数校验。
9. 将 SSD 的 `db` 目录 bind mount 到 `/var/lib/rancher/k3s/server/db`，在 `/etc/fstab` 中声明 `bind,x-systemd.requires-mounts-for=/var/lib/rancher/k3s-ssd`。
10. 启动 `k3s`，确认服务 active、Node `Ready`、Kubernetes API `/readyz` 通过，并验证 embedded etcd 三成员健康。
11. 验证 `findmnt -T /var/lib/rancher/k3s/server/db` 的底层来源属于新 `scsi1`，然后才处理下一台。

原机械盘上的 `server/db` 数据不自动删除。Bind mount 生效后它被覆盖但仍保留在原文件系统中；它只用于迁移失败后的即时回滚，不能在集群继续运行后当作最新副本。长期恢复以迁移前 snapshot 和 PVE 全量备份为准。

## 失败处理与停止点

- Terraform apply、来宾磁盘格式化、K3s 停止和数据迁移都是独立远程写操作，执行时必须分别获得新的明确确认。
- 格式化开关默认关闭；只有预检记录目标设备稳定标识并得到执行确认后才允许开启。
- 任意候选盘条件不满足、snapshot 失败、复制校验不一致、挂载失败、K3s 未恢复、Node 未 Ready 或 etcd 不健康时立即停止整个批次。
- 不自动处理下一节点，不自动删除源数据，也不自动以超时放宽掩盖失败。
- 操作日志只写入脱敏状态、设备稳定标识、校验统计和结果；秘密、Token、kubeconfig 和 Terraform state 只保存在 `.private/`。

## 回滚

单节点在迁移验证完成前失败时：

1. 保持其他节点不变并停止失败节点的 `k3s`。
2. 移除或注释该节点的 bind mount fstab 条目并卸载 bind mount。
3. 取消 SSD 数据盘挂载，恢复原机械盘下未删除的 `server/db`。
4. 启动 `k3s` 并验证 Node 和 etcd 成员恢复。
5. 如果原目录不能恢复，使用迁移前 etcd snapshot 按恢复 runbook 操作。

Terraform 磁盘不在自动回滚中删除。只有确认来宾系统已不依赖 `scsi1`、已有恢复证据且获得新的删除确认后，才允许从 Terraform 配置移除数据盘。

## 测试与验收

### 本地门禁

- Terraform 静态契约验证三个 K3s 节点声明 `SSD1` 上的 20 GiB 数据盘。
- 模块验证独立数据盘 datastore 的回退行为，保证 VM130 不变。
- Ansible 静态契约验证 `hosts: k3s_servers`、`serial: 1`、`any_errors_fatal: true`、候选盘 fail-closed、snapshot、复制校验、bind mount 和健康检查。
- 新迁移 playbook 不得出现在 `site.yml`。
- Terraform fmt、validate、Ansible syntax-check、Bash 3.2 语法检查和 Phase 01 门禁通过。

### 远程验收

- Terraform plan 只新增三块 `SSD1` 上的 20 GiB `scsi1`，无 replace、delete 或其他资源变更。
- VM 120、121、122 均能看到唯一的新 20 GiB 数据盘。
- 三台节点的 `server/db` 均通过 bind mount 落在各自 `scsi1` 的 ext4 文件系统上。
- 三台 K3s 服务 active，Kubernetes Node 全部 `Ready`，API `/readyz` 通过，embedded etcd 三成员健康。
- Argo CD、Harbor、OpenBao、OpenChoreo Portal 和 Observer 入口仍可访问。
- 脱敏操作日志记录每个停止点、执行结果、验证结果和回滚状态。
