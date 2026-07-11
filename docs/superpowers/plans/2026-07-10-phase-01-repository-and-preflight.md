# Phase 01 Repository and Preflight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 建立 openchoreo-infra 的安全仓库骨架、固定版本矩阵，并生成不修改远程状态的 Proxmox、VM、磁盘和 IP 审计证据。

**Architecture:** 仓库契约测试先定义必须存在的文件和敏感路径边界；实现随后补齐目录、版本锁和只读审计脚本。所有真实凭据只从 .private 和环境变量读取，本阶段不执行任何 Proxmox 写操作。

**Tech Stack:** Bash、Git、YAML、jq、yq、OpenSSH、Proxmox CLI 只读命令、gitleaks。

---

## 文件结构

本阶段创建或修改：

- Modify: openchoreo-infra/.gitignore
- Create: openchoreo-infra/.gitleaks.toml
- Create: openchoreo-infra/README.md
- Create: openchoreo-infra/AGENTS.md
- Create: openchoreo-infra/SECURITY.md
- Create: openchoreo-infra/versions.lock.yaml
- Create: openchoreo-infra/inventory/hosts.yaml
- Create: openchoreo-infra/inventory/network.yaml
- Create: openchoreo-infra/inventory/proxmox.yaml
- Create: openchoreo-infra/scripts/lib/common.sh
- Create: openchoreo-infra/scripts/verify/repository.sh
- Create: openchoreo-infra/scripts/verify/secrets.sh
- Create: openchoreo-infra/scripts/verify/versions.sh
- Create: openchoreo-infra/scripts/audit/proxmox-readonly.sh
- Create: openchoreo-infra/scripts/audit/ip-addresses.sh
- Create: openchoreo-infra/scripts/audit/guest-disks.sh
- Create: openchoreo-infra/templates/operation-log.md
- Create: openchoreo-infra/logs/README.md

## Task 1: 先写仓库契约测试

**Files:**

- Create: scripts/verify/repository.sh

- [ ] **Step 1: 写入会失败的契约测试**

~~~bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

required=(
  README.md
  AGENTS.md
  SECURITY.md
  .gitignore
  .gitleaks.toml
  versions.lock.yaml
  inventory/hosts.yaml
  inventory/network.yaml
  inventory/proxmox.yaml
  scripts/lib/common.sh
  scripts/verify/secrets.sh
  scripts/verify/versions.sh
  scripts/audit/proxmox-readonly.sh
  scripts/audit/ip-addresses.sh
  scripts/audit/guest-disks.sh
  templates/operation-log.md
  logs/README.md
)

for path in "${required[@]}"; do
  test -f "$path" || {
    printf 'missing required file: %s\n' "$path" >&2
    exit 1
  }
done

for path in \
  .private/credentials/proxmox.env \
  .private/ssh/id_ed25519 \
  .private/kubeconfigs/admin.yaml \
  .private/terraform-state/terraform.tfstate \
  terraform/environments/homelab/terraform.tfvars; do
  git check-ignore -q "$path" || {
    printf 'sensitive path is not ignored: %s\n' "$path" >&2
    exit 1
  }
done

if git ls-files | rg '(^|/)(\.private/|.*\.tfstate($|\.)|.*\.tfvars$|kubeconfig|.*\.(pem|key)$)' >/dev/null; then
  printf 'tracked sensitive path detected\n' >&2
  exit 1
fi

printf 'repository contract: PASS\n'
~~~

- [ ] **Step 2: 运行测试并确认失败**

Run:

~~~bash
chmod +x scripts/verify/repository.sh
./scripts/verify/repository.sh
~~~

Expected: 返回非零，首个错误为 missing required file: README.md。

- [ ] **Step 3: 只提交测试**

~~~bash
git add scripts/verify/repository.sh
git commit -m "test: enforce infrastructure repository contract"
~~~

## Task 2: 建立敏感信息边界

**Files:**

- Modify: .gitignore
- Create: .gitleaks.toml
- Create: SECURITY.md
- Create: scripts/verify/secrets.sh

- [ ] **Step 1: 扩充 .gitignore**

~~~gitignore
.worktrees/
.private/
*.pem
*.key
*.p12
*.kubeconfig
kubeconfig*
*.tfstate
*.tfstate.*
*.tfvars
!.tfvars.example
.terraform/
.env
.env.*
!.env.example
ansible/vault-password*
*.retry
.DS_Store
~~~

- [ ] **Step 2: 写入 gitleaks 配置**

~~~toml
title = "openchoreo-infra secret scanning"

[extend]
useDefault = true

[[allowlists]]
description = "Allow documented LAN addresses"
regexTarget = "match"
regexes = [
  '''192\.168\.(1|2)\.[0-9]{1,3}'''
]
~~~

- [ ] **Step 3: 写敏感信息验证脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

patterns='BEGIN [A-Z ]*PRIVATE KEY|client-key-data:|client-certificate-data:|api[_-]?token[[:space:]]*[:=][[:space:]]*[^$<{]'

if git grep -n -E "$patterns" -- . \
  ':(exclude)*.example' \
  ':(exclude)docs/superpowers/**'; then
  printf 'possible secret detected in tracked files\n' >&2
  exit 1
fi

if command -v gitleaks >/dev/null 2>&1; then
  gitleaks git --redact --no-banner
else
  printf 'gitleaks unavailable; regex scan only\n'
fi

printf 'secret boundary: PASS\n'
~~~

- [ ] **Step 4: 创建本地私有目录**

~~~bash
install -d -m 0700 \
  .private/credentials \
  .private/ssh \
  .private/kubeconfigs \
  .private/tokens \
  .private/terraform-state \
  .private/pki \
  .private/openbao \
  .private/backups
~~~

Expected: git status 不显示 .private。

- [ ] **Step 5: 写 SECURITY.md**

SECURITY.md 必须包含：

- .private 权限为 0700，文件默认 0600。
- 不在命令行参数中传密码或 Token。
- Terraform 只从 PROXMOX_VE_* 环境变量读取凭据。
- Ansible 使用 SSH key 和 no_log。
- 误提交处理顺序：停止推送、轮换凭据、清理历史、重新扫描、记录事件。

- [ ] **Step 6: 验证并提交**

~~~bash
chmod +x scripts/verify/secrets.sh
git check-ignore -v .private/credentials/proxmox.env
./scripts/verify/secrets.sh
git add .gitignore .gitleaks.toml SECURITY.md scripts/verify/secrets.sh
git commit -m "chore: enforce local secret boundaries"
~~~

Expected: secret boundary: PASS。

## Task 3: 固定版本矩阵

**Files:**

- Create: versions.lock.yaml
- Create: scripts/verify/versions.sh

- [ ] **Step 1: 写入 versions.lock.yaml**

~~~yaml
generated_at: "2026-07-10"
terraform:
  cli: "1.15.8"
  proxmox_provider: "0.111.1"
operating_system:
  ubuntu_release: "24.04"
  cloud_image_url: "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
kubernetes:
  k3s: "v1.35.6+k3s1"
  cilium: "1.19.5"
  kube_vip: "v1.2.1"
  argocd_chart: "10.1.3"
  argocd_app: "3.4.5"
  metallb_chart: "0.16.1"
  ingress_nginx_chart: "4.15.1"
  nfs_csi: "4.13.4"
openchoreo_compatibility:
  gateway_api: "v1.4.1"
  cert_manager: "v1.19.4"
  external_secrets: "2.0.1"
  kgateway: "v2.2.1"
  openbao_chart: "0.25.6"
  openbao_app: "2.4.4"
platform:
  harbor_chart: "1.19.1"
  harbor_app: "2.15.2"
  openchoreo: "1.1.2"
  observability_logs: "0.4.1"
  observability_traces: "0.4.1"
  observability_metrics: "0.6.1"
  crossplane: "2.3.3"
  cloudnative_pg: "1.30.0"
~~~

- [ ] **Step 2: 写版本验证脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

test -f versions.lock.yaml

required_paths=(
  .terraform.cli
  .terraform.proxmox_provider
  .kubernetes.k3s
  .kubernetes.cilium
  .kubernetes.argocd_chart
  .platform.openchoreo
  .platform.harbor_chart
  .platform.crossplane
  .platform.cloudnative_pg
)

for path in "${required_paths[@]}"; do
  value="$(yq -r "$path" versions.lock.yaml)"
  test -n "$value"
  test "$value" != "null"
  case "$value" in
    latest|main|master|nightly|dev)
      printf 'unlocked version: %s=%s\n' "$path" "$value" >&2
      exit 1
      ;;
  esac
done

printf 'version lock: PASS\n'
~~~

- [ ] **Step 3: 验证并提交**

~~~bash
chmod +x scripts/verify/versions.sh
./scripts/verify/versions.sh
git add versions.lock.yaml scripts/verify/versions.sh
git commit -m "chore: lock platform component versions"
~~~

Expected: version lock: PASS。

## Task 4: 建立资产清单

**Files:**

- Create: inventory/hosts.yaml
- Create: inventory/network.yaml
- Create: inventory/proxmox.yaml

- [ ] **Step 1: 写 hosts.yaml**

~~~yaml
all:
  vars:
    ansible_user: ubuntu
    ansible_port: 22
    ansible_become: true
    cluster_name: openchoreo-homelab
    inventory_state: desired
    live_verification_required: true
  children:
    k3s_servers:
      hosts:
        ocp-node-01:
          ansible_host: 192.168.2.180
          vm_id: 120
          k3s_init: true
        ocp-node-02:
          ansible_host: 192.168.2.181
          vm_id: 121
        ocp-node-03:
          ansible_host: 192.168.2.182
          vm_id: 122
    nfs_servers:
      hosts:
        nfs-storage-01:
          ansible_host: 192.168.2.183
          vm_id: 130
~~~

- [ ] **Step 2: 写 network.yaml**

~~~yaml
metadata:
  inventory_state: desired
  live_verification_required: true
subnet: "192.168.0.0/21"
gateway: "192.168.1.1"
bridge: "vmbr0"
kubernetes_api_vip: "192.168.2.179"
internal_domain: "openchoreo.home.arpa"
metallb_pool:
  start: "192.168.2.170"
  end: "192.168.2.178"
service_addresses:
  ingress: "192.168.2.178"
  control_plane: "192.168.2.177"
  dns: "192.168.2.176"
  data_plane: "192.168.2.175"
  observability: "192.168.2.174"
~~~

- [ ] **Step 3: 写 proxmox.yaml**

~~~yaml
metadata:
  inventory_state: desired
  live_verification_required: true
proxmox_endpoint: "https://192.168.2.162:8006/"
node_name: "pve2162"
template_vm_id: 9000
template_name: "ubuntu-2404-cloud-template"
system_datastore_id: "XJ6T"
image_datastore_id: "local"
backup_datastore_id: "PvEDump"
nfs_data_datastore_id: "XJ6T"
~~~

- [ ] **Step 4: 提交资产清单**

~~~bash
git add inventory
git commit -m "docs: record approved infrastructure inventory"
~~~

## Task 5: 创建共享 shell 库

**Files:**

- Create: scripts/lib/common.sh

- [ ] **Step 1: 写 common.sh**

~~~bash
#!/usr/bin/env bash
# Sourcing this library intentionally enables errexit, nounset, and pipefail in the caller.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
    die 'usage: require_command <command>'
  fi
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

require_file() {
  if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
    die 'usage: require_file <path>'
  fi
  test -f "$1" || die "missing file: $1"
}

timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

redact() {
  local key_re='([[:alnum:]_]*([Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt]))'
  sed -E \
    -e "s/(^|[^[:alnum:]_])(((${key_re}))[[:space:]]*=[[:space:]]*)\"[^\"]*\"/\\1\\2\"[redacted]\"/g" \
    -e "s/(^|[^[:alnum:]_])(((${key_re}))[[:space:]]*=[[:space:]]*)'[^']*'/\\1\\2'[redacted]'/g" \
    -e "s/(^|[^[:alnum:]_])(((${key_re}))[[:space:]]*=[[:space:]]*)[^[:space:]&,;\"']+/\\1\\2[redacted]/g" \
    -e "s/(^|[^[:alnum:]_])(\"(${key_re})\"[[:space:]]*:[[:space:]]*)\"([^\"\\\\]|\\\\.)*\"/\\1\\2\"[redacted]\"/g" \
    -e "s/(^|[^[:alnum:]_])(\"(${key_re})\"[[:space:]]*:[[:space:]]*)[^,}\"[:space:]][^,}]*/\\1\\2\"[redacted]\"/g" \
    -e "s/(^|[^[:alnum:]_])(((${key_re}))[[:space:]]*:[[:space:]]*).*/\\1\\2[redacted]/g"
}
~~~

- [ ] **Step 2: 验证 shell 语法并提交**

~~~bash
chmod +x scripts/lib/common.sh
bash -n scripts/lib/common.sh
git add scripts/lib/common.sh
git commit -m "feat: add infrastructure script helpers"
~~~

## Task 6: 创建只读 Proxmox 审计

**Files:**

- Create: scripts/audit/proxmox-readonly.sh

- [ ] **Step 1: 写审计脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

validate_pve_host() {
  if [ "$#" -ne 1 ]; then
    die 'usage: validate_pve_host <destination>'
  fi

  local destination="$1"
  if [ -z "$destination" ]; then
    die 'PVE_SSH_HOST must not be empty'
  fi
  case "$destination" in
    -*|*@-*) die 'PVE_SSH_HOST must not start with a hyphen' ;;
  esac
  if ! [[ "$destination" =~ ^([A-Za-z0-9._-]+@)?([A-Za-z0-9._-]+|[0-9A-Fa-f:]+)$ ]]; then
    die 'PVE_SSH_HOST contains unsafe characters'
  fi
}

build_ssh_args() {
  if [ "$#" -ne 1 ]; then
    die 'usage: build_ssh_args <destination>'
  fi

  ssh_args=(
    ssh
    -F /dev/null
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o ConnectionAttempts=1
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=2
    -o StrictHostKeyChecking=yes
    -o PasswordAuthentication=no
    -o KbdInteractiveAuthentication=no
  )
  if [ -n "${PVE_SSH_IDENTITY_FILE:-}" ]; then
    require_file "$PVE_SSH_IDENTITY_FILE"
    ssh_args+=(
      -i "$PVE_SSH_IDENTITY_FILE"
      -o IdentitiesOnly=yes
    )
  fi
  ssh_args+=(-- "$1")
}

main() {
  local pve_host="${PVE_SSH_HOST-root@192.168.2.162}"

  validate_pve_host "$pve_host"
  require_command ssh
  build_ssh_args "$pve_host"

  printf 'audit_started_at: %s\n' "$(timestamp)"
  printf 'audit_target: %s\n' "$pve_host"

  "${ssh_args[@]}" '
  set -e
  printf "%s\n" "=== pveversion ==="
  pveversion
  printf "%s\n" "=== nodes ==="
  pvesh get /nodes --output-format json
  printf "%s\n" "=== cluster_resources ==="
  resources_json="$(pvesh get /cluster/resources --type vm --output-format json)"
  printf "%s\n" "$resources_json"
  printf "%s\n" "=== storage_status ==="
  pvesm status --output-format json
  for vmid in 120 121 122 130 9000; do
    if printf "%s\n" "$resources_json" |
      grep -Eq "\"vmid\"[[:space:]]*:[[:space:]]*${vmid}([[:space:],}]|$)"; then
      printf "=== vm_%s_config ===\n" "$vmid"
      qm config "$vmid"
    else
      printf "=== vm_%s_free ===\n" "$vmid"
      printf "VMID %s FREE\n" "$vmid"
    fi
  done
  printf "%s\n" "=== backup_jobs ==="
  pvesh get /cluster/backup --output-format json
' 2>&1 | redact
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
~~~

- [ ] **Step 2: 只做语法验证**

~~~bash
chmod +x scripts/audit/proxmox-readonly.sh
bash -n scripts/audit/proxmox-readonly.sh
~~~

Expected: 本步骤不连接远程。

静态验证必须确认远程外部命令仅包含可选的 `hostname`、`pveversion`、`pvesh get`、`pvesm status`、`qm config`、`grep` 和 `printf`，并拒绝所有变更命令。SSH 参数必须包含 `-F /dev/null`、`BatchMode=yes`、`ConnectTimeout=10`、`ConnectionAttempts=1`、`ServerAliveInterval=15`、`ServerAliveCountMax=2`、`StrictHostKeyChecking=yes`、`PasswordAuthentication=no`、`KbdInteractiveAuthentication=no` 和目标前的 `--`；设置身份文件时还必须包含 `-i` 和 `IdentitiesOnly=yes`。

## Task 7: 创建 IP 冲突审计

**Files:**

- Create: scripts/audit/ip-addresses.sh

- [ ] **Step 1: 写 IP 检查脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

print_error_summary() {
  printf 'SUMMARY busy=0 no_response=0 errors=1\n'
}

require_audit_command() {
  if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
    printf 'ERROR audit usage: require_audit_command <command>\n' >&2
    return 2
  fi
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'ERROR audit missing command: %s\n' "$1" >&2
    return 2
  fi
}

load_targets() {
  local output ruby_status
  set +e
  output="$(ruby -ryaml -ripaddr -e '
    network = YAML.safe_load(File.read(ARGV.fetch(0)))
    hosts = YAML.safe_load(File.read(ARGV.fetch(1)))
    raise "network inventory is not a mapping" unless network.is_a?(Hash)
    raise "host inventory is not a mapping" unless hosts.is_a?(Hash)

    pool = network.fetch("metallb_pool")
    first = IPAddr.new(pool.fetch("start"))
    last = IPAddr.new(pool.fetch("end"))
    raise "MetalLB pool must be IPv4" unless first.ipv4? && last.ipv4?
    raise "invalid MetalLB pool bounds" if first.to_i > last.to_i

    values = (first.to_i..last.to_i).map { |value| IPAddr.new(value, Socket::AF_INET).to_s }
    values << IPAddr.new(network.fetch("kubernetes_api_vip")).to_s
    nfs = hosts.fetch("all").fetch("children").fetch("nfs_servers").fetch("hosts")
    values << IPAddr.new(nfs.fetch("nfs-storage-01").fetch("ansible_host")).to_s
    raise "empty IP audit target list" if values.empty?
    raise "duplicate IP audit target" unless values.uniq.length == values.length
    puts values
  ' "$repo_root/inventory/network.yaml" "$repo_root/inventory/hosts.yaml" 2>&1)"
  ruby_status=$?
  set -e
  if [ "$ruby_status" -ne 0 ]; then
    printf 'ERROR inventory %s\n' "$output" >&2
    return 2
  fi

  targets=()
  while IFS= read -r target; do
    [ -n "$target" ] && targets+=("$target")
  done <<< "$output"
  if [ "${#targets[@]}" -eq 0 ]; then
    printf 'ERROR inventory empty IP audit target list\n' >&2
    return 2
  fi
}

configure_platform() {
  if [ "$#" -ne 1 ]; then
    printf 'ERROR audit usage: configure_platform <platform>\n' >&2
    return 2
  fi

  platform="$1"
  case "$platform" in
    Darwin)
      require_audit_command route || return 2
      require_audit_command arp || return 2
      ping_args=(-c 1 -W 1000)
      ping_no_reply_status=2
      route_args=(route -n get)
      neighbor_args=(arp -an)
      neighbor_mode=Darwin
      ;;
    Linux)
      require_audit_command ip || return 2
      ping_args=(-c 1 -W 1)
      ping_no_reply_status=1
      route_args=(ip route get)
      neighbor_args=(ip neigh show)
      neighbor_mode=Linux
      ;;
    *)
      printf 'ERROR audit unsupported platform: %s\n' "$platform" >&2
      return 2
      ;;
  esac
}

record_no_response() {
  printf 'NO_RESPONSE %s\n' "$1"
  no_response_count=$((no_response_count + 1))
}

check_neighbor_cache() {
  local target="$1"
  local neighbor_output neighbor_status entry rg_status target_pattern

  set +e
  neighbor_output="$("${neighbor_args[@]}" 2>&1)"
  neighbor_status=$?
  set -e
  if [ "$neighbor_status" -ne 0 ]; then
    printf 'ERROR neighbor %s rc=%s\n' "$target" "$neighbor_status" >&2
    error_count=$((error_count + 1))
    return
  fi

  set +e
  if [ "$neighbor_mode" = Darwin ]; then
    entry="$(printf '%s\n' "$neighbor_output" | rg -F "($target)")"
  else
    target_pattern="${target//./\\.}"
    entry="$(printf '%s\n' "$neighbor_output" | rg -e "^${target_pattern}([[:space:]]|$)")"
  fi
  rg_status=$?
  set -e
  case "$rg_status" in
    0)
      if [[ "$entry" =~ [Ii][Nn][Cc][Oo][Mm][Pp][Ll][Ee][Tt][Ee] ]] ||
        [[ "$entry" =~ [Ff][Aa][Ii][Ll][Ee][Dd] ]]; then
        record_no_response "$target"
      elif [[ "$entry" =~ [[:xdigit:]]{2}(:[[:xdigit:]]{2}){5} ]] &&
        { [ "$neighbor_mode" = Darwin ] || [[ "$entry" =~ [[:space:]]lladdr[[:space:]] ]]; }; then
        printf 'BUSY neighbor_cache %s\n' "$target"
        busy_count=$((busy_count + 1))
      else
        record_no_response "$target"
      fi
      ;;
    1) record_no_response "$target" ;;
    *)
      printf 'ERROR neighbor_match %s rc=%s\n' "$target" "$rg_status" >&2
      error_count=$((error_count + 1))
      ;;
  esac
}

audit_target() {
  local target="$1"
  local route_output route_status ping_status

  set +e
  route_output="$("${route_args[@]}" "$target" 2>&1)"
  route_status=$?
  set -e
  if [ "$route_status" -ne 0 ]; then
    printf 'ERROR route %s rc=%s\n' "$target" "$route_status" >&2
    error_count=$((error_count + 1))
    return
  fi
  printf 'ROUTE %s\n%s\n' "$target" "$route_output"

  set +e
  ping "${ping_args[@]}" "$target" >/dev/null 2>&1
  ping_status=$?
  set -e
  case "$ping_status" in
    0)
      printf 'BUSY ping %s\n' "$target"
      busy_count=$((busy_count + 1))
      ;;
    *)
      if [ "$ping_status" -eq "$ping_no_reply_status" ]; then
        check_neighbor_cache "$target"
      else
        printf 'ERROR ping %s rc=%s\n' "$target" "$ping_status" >&2
        error_count=$((error_count + 1))
      fi
      ;;
  esac
}

main() {
  if ! require_audit_command ruby; then
    print_error_summary
    return 2
  fi
  if ! load_targets; then
    print_error_summary
    return 2
  fi

  if [ "${IP_AUDIT_DRY_RUN:-0}" = 1 ]; then
    printf 'audit_mode: dry_run\n'
    for target in "${targets[@]}"; do
      printf 'audit_target: %s\n' "$target"
    done
    return 0
  fi

  if ! require_audit_command ping || ! require_audit_command rg ||
    ! require_audit_command uname; then
    print_error_summary
    return 2
  fi
  local detected_platform uname_status
  set +e
  detected_platform="$(uname -s 2>&1)"
  uname_status=$?
  set -e
  if [ "$uname_status" -ne 0 ]; then
    printf 'ERROR audit uname rc=%s\n' "$uname_status" >&2
    print_error_summary
    return 2
  fi
  if ! configure_platform "$detected_platform"; then
    print_error_summary
    return 2
  fi

  busy_count=0
  no_response_count=0
  error_count=0
  printf 'audit_started_at: %s\n' "$(timestamp)"
  printf 'audit_platform: %s\n' "$platform"
  for target in "${targets[@]}"; do
    audit_target "$target"
  done
  printf 'SUMMARY busy=%s no_response=%s errors=%s\n' \
    "$busy_count" "$no_response_count" "$error_count"

  if [ "$error_count" -gt 0 ]; then
    return 2
  fi
  if [ "$busy_count" -gt 0 ]; then
    return 1
  fi
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
~~~

- [ ] **Step 2: 解释预期结果**

退出码 `0` 表示没有确认占用且没有探测错误，`1` 表示至少一个地址被 ping 或带有效 MAC 的邻居缓存证据确认占用，`2` 表示清单、前置命令、平台、路由、ping、邻居缓存或匹配命令发生错误。`NO_RESPONSE` 不能单独证明地址空闲，Darwin ARP 与 Linux `ip neigh` 邻居缓存也都只是时点、非权威证据；正式停止点必须结合路由器租约、主动 ARP 探测和 PVE 配置。

## Task 8: 创建来宾磁盘只读审计

**Files:**

- Create: scripts/audit/guest-disks.sh

- [ ] **Step 1: 写磁盘审计脚本**

~~~bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

device=/dev/sdb

audit_error() {
  printf 'ERROR audit %s\n' "$1" >&2
  printf 'SUMMARY hosts=0 errors=1\n'
  return 2
}

load_hosts() {
  local output status
  set +e
  output="$(ruby -ryaml -e '
    inventory = YAML.safe_load(File.read(ARGV.fetch(0)))
    hosts = inventory.fetch("all").fetch("children").fetch("k3s_servers").fetch("hosts")
    values = hosts.values.map { |entry| entry.fetch("ansible_host") }
    raise "empty guest audit host list" if values.empty?
    raise "duplicate guest audit host" unless values.uniq.length == values.length
    values.each do |value|
      parts = value.to_s.split(".", -1)
      valid = parts.length == 4 && parts.all? { |part| part.match?(/\A(?:0|[1-9][0-9]{0,2})\z/) && part.to_i <= 255 }
      raise "invalid IPv4 address: #{value}" unless valid
    end
    puts values
  ' "$repo_root/inventory/hosts.yaml" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    printf 'ERROR inventory %s\n' "$output" >&2
    return 2
  fi
  hosts=()
  while IFS= read -r host; do
    [ -n "$host" ] && hosts+=("$host")
  done <<< "$output"
  [ "${#hosts[@]}" -gt 0 ] || return 2
}

validate_user() {
  if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
    printf 'ERROR audit invalid SSH user\n' >&2
    return 2
  fi
  if ! [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; then
    printf 'ERROR audit unsafe SSH user: %s\n' "$1" >&2
    return 2
  fi
}

validate_host() {
  if [ "$#" -ne 1 ] || [ -z "${1:-}" ] || [[ "$1" = -* ]] ||
    ! [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    printf 'ERROR audit unsafe SSH host: %s\n' "${1:-}" >&2
    return 2
  fi
}

build_ssh_args() {
  local destination="$1"
  ssh_args=(
    ssh -F /dev/null
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o ConnectionAttempts=1
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=2
    -o StrictHostKeyChecking=yes
    -o PasswordAuthentication=no
    -o KbdInteractiveAuthentication=no
  )
  if [ -n "${GUEST_AUDIT_SSH_IDENTITY_FILE:-}" ]; then
    require_file "$GUEST_AUDIT_SSH_IDENTITY_FILE"
    ssh_args+=(-i "$GUEST_AUDIT_SSH_IDENTITY_FILE" -o IdentitiesOnly=yes)
  fi
  ssh_args+=(-- "$destination")
}

audit_host() {
  local host="$1"
  local destination="$ssh_user@$host"
  local ssh_status
  validate_host "$host" || return 2
  build_ssh_args "$destination"
  printf 'audit_started_at: %s\n' "$(timestamp)"
  printf 'audit_target: %s\n' "$destination"
  printf 'audit_device: %s\n' "$device"
  set +e
  "${ssh_args[@]}" '
    set -eu
    device=/dev/sdb
    for required_command in timeout lsblk findmnt udevadm wipefs blkid readlink; do
      if ! command -v "$required_command" >/dev/null 2>&1; then
        printf "ERROR missing command: %s\n" "$required_command" >&2
        exit 1
      fi
    done
    printf "%s\n" "=== host ==="
    hostname
    printf "%s\n" "=== block_devices ==="
    timeout --foreground 20s lsblk --json --output NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,UUID
    printf "%s\n" "=== mounts ==="
    timeout --foreground 20s findmnt --json
    printf "%s\n" "=== target_device ==="
    if ! test -b "$device"; then
      printf "ERROR missing block device %s\n" "$device" >&2
      exit 1
    fi
    timeout --foreground 20s lsblk --bytes --paths --json \
      --output NAME,KNAME,PATH,MAJ:MIN,SIZE,TYPE,FSTYPE,MOUNTPOINTS,UUID,MODEL,SERIAL,WWN \
      "$device"
    printf "%s\n" "=== udev_properties ==="
    timeout --foreground 20s udevadm info --query=property --name "$device"
    printf "%s\n" "=== disk_by_id ==="
    by_id_found=0
    for by_id_path in /dev/disk/by-id/*; do
      [ -L "$by_id_path" ] || continue
      resolved_path="$(readlink -f "$by_id_path")" || {
        printf "ERROR readlink %s\n" "$by_id_path" >&2
        exit 1
      }
      if [ "$resolved_path" = "$device" ]; then
        printf "%s\n" "$by_id_path"
        by_id_found=1
      fi
    done
    if [ "$by_id_found" -eq 0 ]; then
      printf "NO_BY_ID_LINK %s\n" "$device"
    fi
    printf "%s\n" "=== wipefs ==="
    if wipefs_output="$(timeout --foreground 20s wipefs --no-act --all "$device" 2>&1)"; then
      if [ -n "$wipefs_output" ]; then
        printf "%s\n" "$wipefs_output"
      else
        printf "WIPEFS_NO_SIGNATURE %s\n" "$device"
      fi
    else
      wipefs_status=$?
      printf "ERROR wipefs %s rc=%s\n" "$device" "$wipefs_status" >&2
      exit "$wipefs_status"
    fi
    printf "%s\n" "=== blkid ==="
    if blkid_output="$(timeout --foreground 20s blkid "$device" 2>&1)"; then
      printf "%s\n" "$blkid_output"
    else
      blkid_status=$?
      if [ "$blkid_status" -eq 2 ]; then
        printf "BLKID_NO_RESULT rc=2 %s\n" "$device"
        printf "INCONCLUSIVE_BLKID %s\n" "$device"
      else
        printf "ERROR blkid %s rc=%s\n" "$device" "$blkid_status" >&2
        exit "$blkid_status"
      fi
    fi
  ' 2>&1 | redact
  ssh_status=$?
  set -e
  return "$ssh_status"
}

main() {
  local ssh_user="${GUEST_AUDIT_SSH_USER-root}"
  if ! command -v ruby >/dev/null 2>&1; then
    audit_error 'missing command: ruby'
    return 2
  fi
  if ! load_hosts; then
    printf 'SUMMARY hosts=0 errors=1\n'
    return 2
  fi
  if ! validate_user "$ssh_user"; then
    printf 'SUMMARY hosts=0 errors=1\n'
    return 2
  fi
  if [ -n "${GUEST_AUDIT_SSH_IDENTITY_FILE:-}" ] &&
    [ ! -f "$GUEST_AUDIT_SSH_IDENTITY_FILE" ]; then
    audit_error "missing identity file: $GUEST_AUDIT_SSH_IDENTITY_FILE"
    return 2
  fi

  if [ "${GUEST_AUDIT_DRY_RUN:-0}" = 1 ]; then
    printf 'audit_mode: dry_run\n'
    for host in "${hosts[@]}"; do
      validate_host "$host" || return 2
      printf 'audit_target: %s@%s\n' "$ssh_user" "$host"
      printf 'audit_device: %s\n' "$device"
    done
    return 0
  fi

  if ! command -v ssh >/dev/null 2>&1; then
    audit_error 'missing command: ssh'
    return 2
  fi
  error_count=0
  for host in "${hosts[@]}"; do
    if ! audit_host "$host"; then
      error_count=$((error_count + 1))
    fi
  done
  printf 'SUMMARY hosts=%s errors=%s\n' "${#hosts[@]}" "$error_count"
  [ "$error_count" -eq 0 ] || return 2
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
~~~

- [ ] **Step 2: 语法验证**

~~~bash
chmod +x scripts/audit/ip-addresses.sh scripts/audit/guest-disks.sh
bash -n scripts/audit/ip-addresses.sh
bash -n scripts/audit/guest-disks.sh
~~~

设置 `GUEST_AUDIT_DRY_RUN=1` 时只输出由清单生成的三个 SSH 目标和固定设备 `/dev/sdb`，不会连接主机。正常执行退出码 `0` 表示三台主机的只读审计均成功，退出码 `2` 表示至少一台主机或前置验证失败；脚本会继续审计其余主机并输出汇总。实时运行要求目标已写入 `known_hosts`，且 SSH agent、默认密钥或 `GUEST_AUDIT_SSH_IDENTITY_FILE` 可用。输出仅是磁盘证据，不会自动判定设备为空；任何删除决策前必须结合 PVE 磁盘映射人工复核。

设备大小、序列号、WWN、`/dev/disk/by-id` 路径和 major:minor 必须与 PVE `qm config` 及存储证据交叉核对后才能考虑删除。`WIPEFS_NO_SIGNATURE`、`NO_BY_ID_LINK` 和 blkid 退出码 2 所产生的 `BLKID_NO_RESULT`/`INCONCLUSIVE_BLKID` 都不能单独证明磁盘为空；任何超时或其他命令错误均使该主机审计失败。

## Task 9: 建立入口文档和日志模板

**Files:**

- Create: README.md
- Create: AGENTS.md
- Create: templates/operation-log.md
- Create: logs/README.md

- [ ] **Step 1: 写 README 导航**

README 必须链接：

- 最终架构设计。
- 总控计划和五份阶段计划。
- inventory。
- Terraform、Ansible、GitOps 入口。
- 只读审计脚本。
- 恢复 Runbook。
- .private 使用方式。

- [ ] **Step 2: 写项目级 AGENTS.md**

必须规定：

- 文档使用中文。
- 任何删除、重装、关机、磁盘格式化、网络变更、Terraform apply 都必须在执行时再次确认。
- 所有远程写操作记录日志。
- 禁止 git add -A。
- 每次只显式暂存当前任务文件。

- [ ] **Step 3: 写 operation-log 模板**

~~~markdown
# 操作日志

- 时间：
- 操作者：
- 目标：
- 授权：
- 变更前事实：
- 运行命令：
- 脱敏结果：
- 验证：
- 回滚：
- 下一停止点：
~~~

- [ ] **Step 4: 提交**

~~~bash
git add README.md AGENTS.md templates/operation-log.md logs/README.md
git commit -m "docs: add infrastructure operations entrypoints"
~~~

## Task 10: 完成本地验证

- [ ] **Step 1: 运行全部静态检查**

~~~bash
./scripts/verify/repository.sh
./scripts/verify/secrets.sh
./scripts/verify/versions.sh
find scripts -name '*.sh' -print0 | xargs -0 -n1 bash -n
ip_dry_run="$(IP_AUDIT_DRY_RUN=1 ./scripts/audit/ip-addresses.sh)"
test "$(grep -c '^audit_target: ' <<<"$ip_dry_run")" -eq 11
guest_dry_run="$(GUEST_AUDIT_DRY_RUN=1 ./scripts/audit/guest-disks.sh)"
test "$(grep -c '^audit_target: ' <<<"$guest_dry_run")" -eq 3
test "$(grep -c '^audit_device: /dev/sdb$' <<<"$guest_dry_run")" -eq 3
git diff --check
~~~

Expected:

    repository contract: PASS
    secret boundary: PASS
    version lock: PASS

Proxmox 审计在本地门禁中只做 `bash -n` 和 source 后的主机/SSH argv 函数测试，绝不执行 `main` 或发起 SSH。两个 dry-run 输出只能包含模式、目标和固定设备标签，不得出现 ping、ARP、路由或 SSH 执行证据。

- [ ] **Step 2: 核对跟踪状态和 Phase 01 提交**

~~~bash
required=(
  README.md AGENTS.md SECURITY.md .gitignore .gitleaks.toml versions.lock.yaml
  inventory/hosts.yaml inventory/network.yaml inventory/proxmox.yaml
  scripts/lib/common.sh scripts/verify/repository.sh scripts/verify/secrets.sh
  scripts/verify/versions.sh scripts/audit/proxmox-readonly.sh
  scripts/audit/ip-addresses.sh scripts/audit/guest-disks.sh
  templates/operation-log.md logs/README.md
)
git ls-files --error-unmatch "${required[@]}"
git status --short
git log --reverse --format='%h %s' e5eaf06^..HEAD

# 如果当前唯一变化是本计划校正，则只显式提交该文件。
git add docs/superpowers/plans/2026-07-10-phase-01-repository-and-preflight.md
git commit -m "docs: align Phase 01 validation gate"

# 提交后不得遗留本任务产生的未暂存、暂存或未跟踪内容。
git diff --exit-code
git diff --cached --exit-code
git status --short
~~~

Expected: 所有 Phase 01 必需路径均已跟踪；提交历史逐项列出 Phase 01 的频繁小提交；提交后 worktree 不含本任务产生的残留。

- [ ] **Step 3: 推送并停止**

~~~bash
git push origin codex/openchoreo-platform
~~~

在用户执行时重新明确批准实时只读审计，并确认 SSH 密钥和 `known_hosts` 前置条件之前，不运行 `scripts/audit/` 下会连接远程或探测网络的命令。
