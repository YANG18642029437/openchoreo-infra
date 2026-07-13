---
date: 2026-07-13
operator: Codex with user approval
scope: K3s VM 120, 121, 122 root filesystem mount options
risk: medium
status: completed-with-known-limitation
---

# K3s 机械盘最小调优执行记录

## 审批与边界

- 用户在远程写入前明确确认执行。
- 只修改三台 K3s 节点的根文件系统挂载选项，并启用已有的 `fstrim.timer`。
- 未修改 PVE 存储、虚拟磁盘、Terraform state、SSD、PVC 或应用配置。
- 未格式化、卸载、删除、重启 VM 或停止 K3s。

## 执行前保护

- PVE API 只读核对到 VM 120、121、122 在 2026-07-11 的全量备份，大小分别约为 3.24 GiB、3.01 GiB 和 1.09 GiB。
- 原 `.private/backups` 严格 manifest 已不存在，因此未把旧 manifest 验证器结果冒充为本次证据；以 PVE API 当前卷记录和既有仓库日志交叉核对。
- 2026-07-13 14:21:18 +08:00 创建新的 etcd snapshot：
  `pre-hdd-tuning-20260713T062111Z-ocp-node-01-1783923678`，大小 34,209,824 bytes。

## 执行过程

第一次滚动执行在 `ocp-node-01` 完成调优后，本地委派的 `kubectl wait` 错误继承了远端 `ansible_become: true`，导致 macOS 控制端请求 sudo 密码。任务按 `any_errors_fatal: true` 停止，未继续修改后两台节点。

为该问题加入静态回归契约，并在两个本地委派任务上显式设置 `ansible_become: false`。再次执行后，`ocp-node-01` 保持幂等，随后依次完成 `ocp-node-02` 和 `ocp-node-03`。

## 节点结果

| 节点 | `/etc/fstab` 根挂载 | 实时根挂载 | `fstrim.timer` | Kubernetes Node |
|---|---|---|---|---|
| `ocp-node-01` | `defaults,commit=30,errors=remount-ro` | 无 `discard` | enabled / active | Ready |
| `ocp-node-02` | `defaults,commit=30,errors=remount-ro` | 无 `discard` | enabled / active | Ready |
| `ocp-node-03` | `defaults,commit=30,errors=remount-ro` | 无 `discard` | enabled / active | Ready |

五个浏览器入口在执行后均返回 HTTP 200：Argo CD、Harbor、OpenBao、OpenChoreo Portal 和 Observer。

## 已知限制：embedded etcd 仍受机械盘延迟影响

Kubernetes API `/readyz` 没有达到连续稳定通过：40 秒内 8 次采样为 3 次通过、5 次失败，失败项在 `etcd` 或 `etcd-readiness`。三台节点仍维持 Ready，五个入口持续可访问。

只读诊断显示三台虚拟盘短时 `%util` 接近 100%，`iowait` 约 30%–74%，小块写入 `w_await` 约 200–470 ms，并出现大量 `slow fdatasync` 和 ReadIndex 重试。调优前的 13:50–14:00 窗口已经存在这些告警：

| 节点 | `slow fdatasync` | slow apply | ReadIndex retry |
|---|---:|---:|---:|
| `ocp-node-01` | 88 | 3553 | 692 |
| `ocp-node-02` | 144 | 2912 | 880 |
| `ocp-node-03` | 119 | 2424 | 785 |

因此该抖动属于本次变更前已经存在的共享机械盘性能瓶颈，而不是取消持续 `discard` 后新产生的故障。本次最小调优减少了持续 discard，但不能消除 etcd 强制同步写入的物理延迟。

应用状态中仍可见既有的 Cilium operator、OpenChoreo controller-manager 和 kgateway CrashLoopBackOff；Argo CD 中 `kgateway` 与 `openchoreo-control-plane` 仍为 Progressing，`openbao` 为 OutOfSync/Healthy。它们不在本次配置变更范围内。

## 回滚结论

未触发回滚：三台节点和入口均可用，且慢盘证据明确早于本次变更。恢复持续 `discard` 只会重新增加在线 trim 压力，不能修复 etcd 的同步写延迟。

若后续要求 `/readyz` 稳定通过，需要另立变更范围，优先选择确认 SSD 用途后迁移 etcd，或缩减实验集群内的高写入工作负载；本次没有擅自执行这些扩大范围的操作。

## 本地验证

- HDD 调优静态契约：PASS。
- Ansible syntax check：PASS。
- ansible-lint production profile：0 failures、0 warnings。
- Phase 01 本地门禁：PASS。
- 敏感信息正则扫描：PASS；本机未安装 gitleaks，因此历史扫描保证等级为 reduced。
- `git diff --check`：PASS。
