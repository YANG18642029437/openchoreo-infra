#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/proxmox-api.sh"

latest_backup_volume() {
  local vmid="$1"
  python3 -c '
import json, sys
vmid = int(sys.argv[1])
data = json.load(sys.stdin).get("data")
if not isinstance(data, list):
    raise SystemExit("Proxmox storage response did not contain a list data field")
candidates = []
for item in data:
    if not isinstance(item, dict):
        continue
    volid = item.get("volid", "")
    try:
        size = int(item.get("size", 0))
        ctime = int(item.get("ctime", 0))
        item_vmid = int(item.get("vmid", vmid))
    except (TypeError, ValueError):
        continue
    if item_vmid == vmid and size > 0 and "vzdump-qemu" in volid:
        candidates.append((ctime, volid))
if not candidates:
    raise SystemExit(f"no non-empty vzdump-qemu backup found for VM {vmid}")
print(max(candidates)[1])
' "$vmid"
}

main() {
  proxmox_api_init

  local node="${PROXMOX_BACKUP_NODE:-pve2162}"
  local storage="${PROXMOX_BACKUP_STORAGE:-PvEDump}"
  local vmids="${PROXMOX_BACKUP_VMIDS:-120 121 122}"

  [[ "$node" =~ ^[A-Za-z0-9._-]+$ ]] || proxmox_api_die 'unsafe backup node name'
  [[ "$storage" =~ ^[A-Za-z0-9._-]+$ ]] || proxmox_api_die 'unsafe backup storage name'

  local vmid response volume
  for vmid in $vmids; do
    [[ "$vmid" =~ ^[1-9][0-9]*$ ]] || proxmox_api_die 'invalid VM ID in PROXMOX_BACKUP_VMIDS'
    response="$(proxmox_api_get "/nodes/${node}/storage/${storage}/content" content backup vmid "$vmid")"
    volume="$(printf '%s' "$response" | latest_backup_volume "$vmid")"
    printf 'BACKUP_OK vmid=%s volume=%s\n' "$vmid" "$volume"
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
