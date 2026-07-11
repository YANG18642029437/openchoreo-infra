#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/common.sh"

require_command ssh
require_command jq

pve_host="${PVE_SSH_HOST:-root@192.168.2.162}"

ssh -o BatchMode=yes "$pve_host" '
  set -e
  pveversion
  pvesh get /nodes --output-format json
  pvesm status --output-format json
  for vmid in 120 121 122 130 9000; do
    if qm status "$vmid" >/dev/null 2>&1; then
      qm config "$vmid"
    else
      printf "VMID %s FREE\n" "$vmid"
    fi
  done
  pvesh get /cluster/backup --output-format json
' | redact
