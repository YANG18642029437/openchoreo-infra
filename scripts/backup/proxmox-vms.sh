#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/proxmox-api.sh"

main() {
  proxmox_api_init

  local node="${PROXMOX_BACKUP_NODE:-pve2162}"
  local storage="${PROXMOX_BACKUP_STORAGE:-PvEDump}"
  local vmids="${PROXMOX_BACKUP_VMIDS:-120 121 122}"
  local poll_interval="${PROXMOX_BACKUP_POLL_INTERVAL:-2}"
  local max_polls="${PROXMOX_BACKUP_MAX_POLLS:-900}"
  local note_time
  note_time="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  [[ "$node" =~ ^[A-Za-z0-9._-]+$ ]] || proxmox_api_die 'unsafe backup node name'
  [[ "$storage" =~ ^[A-Za-z0-9._-]+$ ]] || proxmox_api_die 'unsafe backup storage name'
  [[ "$poll_interval" =~ ^[0-9]+([.][0-9]+)?$ ]] || proxmox_api_die 'invalid backup poll interval'
  [[ "$max_polls" =~ ^[1-9][0-9]*$ ]] || proxmox_api_die 'invalid backup poll limit'

  local vmid
  for vmid in $vmids; do
    [[ "$vmid" =~ ^[1-9][0-9]*$ ]] || proxmox_api_die 'invalid VM ID in PROXMOX_BACKUP_VMIDS'

    local response upid encoded_upid poll status_line status exitstatus
    response="$(proxmox_api_post "/nodes/${node}/vzdump" \
      vmid "$vmid" \
      storage "$storage" \
      mode snapshot \
      compress zstd \
      remove 0 \
      notes-template "OpenChoreo API backup ${note_time}")"
    upid="$(printf '%s' "$response" | proxmox_api_json_data_string)"
    encoded_upid="$(proxmox_api_urlencode "$upid")"

    status=''
    exitstatus=''
    for ((poll = 1; poll <= max_polls; poll++)); do
      status_line="$(proxmox_api_get "/nodes/${node}/tasks/${encoded_upid}/status" | proxmox_api_json_task_status)"
      IFS=$'\t' read -r status exitstatus <<<"$status_line"
      if [ "$status" = stopped ]; then
        break
      fi
      sleep "$poll_interval"
    done

    [ "$status" = stopped ] || proxmox_api_die "backup task timed out for VM ${vmid}"
    [ "$exitstatus" = OK ] || proxmox_api_die "backup task failed for VM ${vmid}: ${exitstatus:-unknown}"
    printf 'BACKUP_TASK_OK vmid=%s\n' "$vmid"
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
