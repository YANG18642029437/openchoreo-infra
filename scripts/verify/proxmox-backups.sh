#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/proxmox-api.sh"

latest_backup_volume() {
  local vmid="$1"
  local start_epoch="$2"
  python3 -c '
import json, sys
vmid = int(sys.argv[1])
start_epoch = int(sys.argv[2])
data = json.load(sys.stdin).get("data")
if not isinstance(data, list):
    raise SystemExit("Proxmox storage response did not contain a list data field")
candidates = []
for item in data:
    if not isinstance(item, dict):
        continue
    volid = item.get("volid", "")
    if not isinstance(volid, str):
        continue
    try:
        size = int(item.get("size", 0))
        ctime = int(item.get("ctime", 0))
        item_vmid = int(item["vmid"])
    except (TypeError, ValueError):
        continue
    except KeyError:
        continue
    marker = f"vzdump-qemu-{vmid}-"
    if item_vmid == vmid and size > 0 and ctime >= start_epoch and marker in volid:
        candidates.append((ctime, volid))
if not candidates:
    raise SystemExit(f"no matching backup newer than the manifest start time for VM {vmid}")
print(max(candidates)[1])
' "$vmid" "$start_epoch"
}

manifest_record() {
  local manifest="$1"
  local vmid="$2"
  python3 -c '
import csv, re, sys
path, vmid = sys.argv[1], int(sys.argv[2])
with open(path, newline="", encoding="utf-8") as stream:
    rows = list(csv.DictReader(stream, delimiter="\t"))
matches = [row for row in rows if row.get("vmid", "").isdigit() and int(row["vmid"]) == vmid]
if len(matches) != 1:
    raise SystemExit(f"manifest must contain exactly one record for VM {vmid}")
row = matches[0]
try:
    start_epoch = int(row["start_epoch"])
except (KeyError, TypeError, ValueError):
    raise SystemExit(f"manifest contains an invalid start time for VM {vmid}")
upid = row.get("upid", "")
if start_epoch <= 0 or not re.fullmatch(r"UPID:[A-Za-z0-9._-]+:[!-~]+", upid):
    raise SystemExit(f"manifest contains an incomplete record for VM {vmid}")
print(f"{start_epoch}\t{upid}")
' "$manifest" "$vmid"
}

main() {
  proxmox_api_init

  local node="${PROXMOX_BACKUP_NODE:-pve2162}"
  local storage="${PROXMOX_BACKUP_STORAGE:-PvEDump}"
  local vmids="${PROXMOX_BACKUP_VMIDS:-120 121 122}"
  : "${PVE_BACKUP_MANIFEST:?PVE_BACKUP_MANIFEST must identify the completed backup run}"
  local manifest="$PVE_BACKUP_MANIFEST"

  [[ "$node" =~ ^[A-Za-z0-9._-]+$ ]] || proxmox_api_die 'unsafe backup node name'
  [[ "$storage" =~ ^[A-Za-z0-9._-]+$ ]] || proxmox_api_die 'unsafe backup storage name'
  [ -f "$manifest" ] || proxmox_api_die "backup manifest not found: ${manifest}"

  local vmid response volume start_epoch upid manifest_line
  for vmid in $vmids; do
    [[ "$vmid" =~ ^[1-9][0-9]*$ ]] || proxmox_api_die 'invalid VM ID in PROXMOX_BACKUP_VMIDS'
    manifest_line="$(manifest_record "$manifest" "$vmid")"
    IFS=$'\t' read -r start_epoch upid <<<"$manifest_line"
    response="$(proxmox_api_get "/nodes/${node}/storage/${storage}/content" content backup vmid "$vmid")"
    volume="$(printf '%s' "$response" | latest_backup_volume "$vmid" "$start_epoch")"
    printf 'BACKUP_OK vmid=%s volume=%s upid=%s\n' "$vmid" "$volume" "$upid"
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
