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
  if ! command -v timeout >/dev/null 2>&1; then
    printf "%s\n" "ERROR missing command: timeout" >&2
    exit 1
  fi
  printf "%s\n" "=== pveversion ==="
  timeout --foreground 20s pveversion
  printf "%s\n" "=== nodes ==="
  timeout --foreground 20s pvesh get /nodes --output-format json
  printf "%s\n" "=== cluster_resources ==="
  resources_json="$(timeout --foreground 20s pvesh get /cluster/resources --type vm --output-format json)"
  printf "%s\n" "$resources_json"
  printf "%s\n" "=== storage_status ==="
  timeout --foreground 20s pvesm status --output-format json
  for vmid in 120 121 122 130 9000; do
    if printf "%s\n" "$resources_json" |
      grep -Eq "\"vmid\"[[:space:]]*:[[:space:]]*${vmid}([[:space:],}]|$)"; then
      printf "=== vm_%s_config ===\n" "$vmid"
      timeout --foreground 20s qm config "$vmid"
    else
      printf "=== vm_%s_free ===\n" "$vmid"
      printf "VMID %s FREE\n" "$vmid"
    fi
  done
  printf "%s\n" "=== backup_jobs ==="
  timeout --foreground 20s pvesh get /cluster/backup --output-format json
' 2>&1 | redact
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
